-- lua/lvim-qf-loc/qf/preview.lua
-- The NATIVE-view preview — nvim-bqf's floating preview of the entry under the cursor, but built on plain,
-- public Neovim window APIs: NO LuaJIT FFI and NO "magicwin" scroll math (bqf's two crash sources). One
-- reusable float shows the entry's REAL file buffer (so syntax highlighting + folds are free and live),
-- scrolled to the entry with its line highlighted; it follows the quickfix cursor and closes with the list.
-- Positioned just above the quickfix window, clamped to the screen — every window op is guarded.
--
---@module "lvim-qf-loc.qf.preview"

local api = vim.api
local config = require("lvim-qf-loc.config")

local M = {}

---@type integer? the reusable float window
local win
---@type integer? a fallback scratch buffer (only used when an entry has no real file)
local scratch

--- Define the footer highlight groups from the lvim-utils palette (file = blue, labels = yellow, numbers =
--- green, separators dim, the ➤ marker an accent) so they track the theme; when lvim-utils is absent, link to
--- always-present groups. Idempotent — safe to call again on a colorscheme change.
local function define_highlights()
    local okc, c = pcall(require, "lvim-utils.colors")
    local okh, hl = pcall(require, "lvim-utils.highlight")
    if okc and okh and c.blue then
        -- one blue foreground for the whole title (text + separators), on the blue tint background (the
        -- lvim-utils convention: the accent blended 0.3 toward the bg)
        local tint = hl.blend(c.blue, c.bg, 0.3)
        hl.register({
            LvimQfLocPreviewFile = { fg = c.blue, bold = true, bg = tint },
            LvimQfLocPreviewLabel = { fg = c.blue, bg = tint },
            LvimQfLocPreviewNum = { fg = c.blue, bg = tint },
            LvimQfLocPreviewSep = { fg = c.blue, bg = tint },
            LvimQfLocPreviewMarker = { fg = c.orange, bold = true },
        })
    else
        local links = {
            LvimQfLocPreviewFile = "Directory",
            LvimQfLocPreviewLabel = "Directory",
            LvimQfLocPreviewNum = "Directory",
            LvimQfLocPreviewSep = "Directory",
            LvimQfLocPreviewMarker = "Special",
        }
        for name, link in pairs(links) do
            pcall(api.nvim_set_hl, 0, name, { link = link, default = true })
        end
    end
end

--- Install the footer highlights + re-apply them on a colorscheme/palette change.
function M.setup()
    -- One-time cleanup: an earlier version set the ➤ marker + line highlight as BUFFER extmarks on the real
    -- file buffers, which leaked (and a sign-aware statuscolumn then hid the line number). Clear any leftovers
    -- so a plugin reload (not a full restart) recovers without the stale signs.
    local stale = api.nvim_create_namespace("lvim-qf-loc-preview")
    for _, b in ipairs(api.nvim_list_bufs()) do
        if api.nvim_buf_is_valid(b) then
            pcall(api.nvim_buf_clear_namespace, b, stale, 0, -1)
        end
    end
    define_highlights()
    api.nvim_create_autocmd("ColorScheme", {
        group = api.nvim_create_augroup("LvimQfLocPreviewHl", { clear = true }),
        callback = define_highlights,
    })
    local ok, colors = pcall(require, "lvim-utils.colors")
    if ok and type(colors.on_change) == "function" then
        pcall(colors.on_change, define_highlights)
    end
end

--- The PREVIEW float's own border, resolved from `config.preview.border` (the title-canon top " " edge that
--- carries the centered border-title). It is run through `lvim-utils.ui.util.resolve_border` (the chassis
--- normalizer) because the padded representation — empty corners between " " edges — is rejected by
--- `nvim_open_win` directly. Falls back to a plain "rounded" string when lvim-utils is absent.
---@return string|string[]
local function preview_border()
    local ok, util = pcall(require, "lvim-utils.ui.util")
    if ok and util.resolve_border then
        return util.resolve_border(config.preview.border)
    end
    return "rounded" -- standalone fallback (lvim-utils absent; a native string border nvim accepts as-is)
end

--- The centered TOP title: `<file> ➤ line <lnum> ➤ col <col>` as a coloured box — tight (no column padding).
---@param entry table
---@return table[]  title chunks for nvim_open_win
local function title_chunks(entry)
    local name = (entry.bufnr and entry.bufnr > 0 and api.nvim_buf_is_valid(entry.bufnr))
            and api.nvim_buf_get_name(entry.bufnr)
        or ""
    local file = name ~= "" and vim.fn.fnamemodify(name, ":t") or "[no name]"
    local chunks = { { " " .. file .. " ", "LvimQfLocPreviewFile" } }
    -- the position (line │ col) only makes sense for a match list (grep / references); for diagnostics it is
    -- noise, so by default ("auto") it is shown only when the entry has no severity type.
    local pos = config.preview.position
    if pos == "always" or (pos ~= "never" and (entry.type or "") == "") then
        local lnum = (entry.lnum and entry.lnum > 0) and entry.lnum or 1
        local col = (entry.col and entry.col > 0) and entry.col or 1
        chunks[#chunks + 1] = { "➤ ", "LvimQfLocPreviewSep" }
        chunks[#chunks + 1] = { "line ", "LvimQfLocPreviewLabel" }
        chunks[#chunks + 1] = { tostring(lnum), "LvimQfLocPreviewNum" }
        chunks[#chunks + 1] = { " ➤ ", "LvimQfLocPreviewSep" }
        chunks[#chunks + 1] = { "col ", "LvimQfLocPreviewLabel" }
        chunks[#chunks + 1] = { tostring(col) .. " ", "LvimQfLocPreviewNum" }
    end
    return chunks
end

--- Close the preview float (idempotent).
function M.close()
    if win and api.nvim_win_is_valid(win) then
        pcall(api.nvim_win_close, win, true)
    end
    win = nil
end

--- Scroll the floating preview by a half-page (`delta > 0` down, `< 0` up) WITHOUT leaving the quickfix list —
--- a peek at more context around the entry. No-op when the preview is closed. Moving the list cursor re-centres
--- the preview on the new entry, so the scroll is transient.
---@param delta integer
function M.scroll(delta)
    if not (win and api.nvim_win_is_valid(win)) then
        return
    end
    local key = api.nvim_replace_termcodes(delta > 0 and "<C-d>" or "<C-u>", true, false, true)
    pcall(api.nvim_win_call, win, function()
        vim.cmd("normal! " .. key)
    end)
end

--- The geometry for the float: full width of the quickfix window, stacked just ABOVE it, using whatever
--- height is free between the top of the screen and the quickfix window. nil when there isn't room.
---@param qwin integer
---@return table? config  an nvim_open_win config
local function geometry(qwin)
    if not api.nvim_win_is_valid(qwin) then
        return nil
    end
    local pos = api.nvim_win_get_position(qwin) -- { row, col } of the qf window, screen-relative
    local qrow, qcol = pos[1], pos[2]
    local width = api.nvim_win_get_width(qwin)
    local qheight = api.nvim_win_get_height(qwin)
    -- Stack the preview into whichever side has more room — ABOVE the qf window (the usual case, qf at the
    -- bottom) or BELOW it (qf at the top / in the middle). 1-row gaps; the qf's own statusline sits at
    -- `qrow + qheight`. Without this, a quickfix opened at the top of the screen had no room above and the
    -- preview never appeared.
    local screen_bottom = vim.o.lines - vim.o.cmdheight - 1 -- last usable screen row (0-based), above the cmdline
    -- The float's actual BORDER rows: top + bottom edges of the resolved border (the title-canon = 1, top only;
    -- a full ring = 2; "none" = 0). The reserve + the above-stack offset MUST follow this — the preview sits
    -- DIRECTLY against the qf window (its top title border is the only chrome), so no stray empty gap rows.
    local border = preview_border()
    local btop = (type(border) == "table") and (((border[2] or "") ~= "") and 1 or 0) or 1
    local bbot = (type(border) == "table") and (((border[6] or "") ~= "") and 1 or 0) or 1
    local brows = btop + bbot
    -- Usable CONTENT rows on each side, after reserving only the border rows (the title border is the separator).
    local above = (qrow - 1) - brows
    local below = (screen_bottom - (qrow + qheight + 1)) - brows
    local height, row
    if below >= above then
        height = math.min(config.preview.max_height, below)
        row = qrow + qheight + 1 -- directly below the qf statusline; nvim adds the float's own (title) border
    else
        height = math.min(config.preview.max_height, above)
        row = qrow - height - brows -- content + border sits directly above the qf window (no extra gap)
    end
    if height < 3 then
        return nil
    end
    return {
        relative = "editor",
        row = row,
        col = qcol,
        width = math.max(1, width),
        height = height,
        focusable = false,
        style = "minimal",
        border = border,
        zindex = 50,
    }
end

--- Show/refresh the preview for `entry` (a quickfix item) anchored above `qwin`. Closes when there is nothing
--- to show.
---@param entry table?
---@param qwin integer
function M.update(entry, qwin)
    if not config.preview.enabled or not entry then
        M.close()
        return
    end
    local geo = geometry(qwin)
    if not geo then
        M.close()
        return
    end
    geo.title = title_chunks(entry) -- the centered `file │ line N │ col M` box, on the TOP border
    geo.title_pos = "center"
    -- the buffer to show: the entry's real file (full syntax, live), else a scratch with the entry text
    local buf
    if
        entry.bufnr
        and entry.bufnr > 0
        and api.nvim_buf_is_valid(entry.bufnr)
        and api.nvim_buf_get_name(entry.bufnr) ~= ""
    then
        buf = entry.bufnr
        pcall(vim.fn.bufload, buf)
        -- make the preview SYNTAX-HIGHLIGHTED: ensure the buffer has its filetype, then start treesitter (with
        -- a syntax fallback). A file opened only via bufload may have neither, so the content shows plain.
        if vim.bo[buf].filetype == "" then
            local ft = vim.filetype.match({ buf = buf })
                or vim.filetype.match({ filename = api.nvim_buf_get_name(buf) })
            if ft and ft ~= "" then
                vim.bo[buf].filetype = ft
            end
        end
        if not pcall(vim.treesitter.start, buf) and vim.bo[buf].syntax == "" and vim.bo[buf].filetype ~= "" then
            pcall(function()
                vim.bo[buf].syntax = vim.bo[buf].filetype
            end)
        end
    else
        if not (scratch and api.nvim_buf_is_valid(scratch)) then
            scratch = api.nvim_create_buf(false, true)
        end
        buf = scratch
        pcall(api.nvim_buf_set_lines, buf, 0, -1, false, { entry.text or "" })
    end

    if win and api.nvim_win_is_valid(win) then
        pcall(api.nvim_win_set_config, win, geo)
        pcall(api.nvim_win_set_buf, win, buf)
    else
        local ok, w = pcall(api.nvim_open_win, buf, false, geo)
        if not ok then
            return
        end
        win = w
    end
    -- A POSITIONED entry (grep / diagnostics / references) marks its focused line with the ➤ sign + the
    -- cursorline highlight; a plain FILE entry has no specific line, so it shows NEITHER — just line numbers.
    local positioned = (entry.lnum and entry.lnum > 0) and true or false
    -- window-local look (guarded; a no-name scratch can reject some)
    pcall(function()
        vim.wo[win].number = false -- the statuscolumn below renders the number (with the ➤ marker)
        vim.wo[win].relativenumber = false
        vim.wo[win].cursorline = positioned
        vim.wo[win].cursorlineopt = "both"
        vim.wo[win].signcolumn = "no"
        vim.wo[win].foldenable = false
        vim.wo[win].wrap = false
        vim.wo[win].winbar = "%#NormalFloat# " -- one blank "air" row under the title, in the float's own bg
        -- The entry marker + line number live in a WINDOW-LOCAL statuscolumn, and the focused-line highlight
        -- in cursorline (mapped to config.preview.hl) — NOT buffer extmarks, which would leak the ➤ sign and the
        -- highlight onto the real file buffer (and hide the line number in a sign-aware statuscolumn). For a
        -- file entry the marker column is blank (no ➤).
        local marker = positioned and "%{% v:relnum == 0 ? '%#LvimQfLocPreviewMarker#➤' : ' ' %}" or " "
        vim.wo[win].statuscolumn = marker .. " %#LineNr#%{v:lnum} "
        vim.wo[win].winhighlight = "CursorLine:" .. config.preview.hl
    end)
    -- scroll to the entry + centre it, and highlight its line
    local lnum = (entry.lnum and entry.lnum > 0) and entry.lnum or 1
    pcall(api.nvim_win_call, win, function()
        pcall(api.nvim_win_set_cursor, win, { lnum, math.max(0, (entry.col or 1) - 1) })
        vim.cmd("normal! zz")
    end)
end

return M
