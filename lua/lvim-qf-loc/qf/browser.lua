-- lua/lvim-qf-loc/qf/browser.lua
-- The quickfix / location-list BROWSER — a live preview of the entry under the cursor, built on the
-- lvim-utils stack: the list + a REAL-Neovim preview open in OUR area (the surface chassis, same
-- zone as the pickers and the lsp navigation), NOT a native qf float, and with neither LuaJIT FFI
-- nor scroll math against the window's internals (the brittle, crash-prone parts of the usual
-- implementations, deliberately dropped). The list is the
-- lvim-picker list — so it comes with fuzzy narrowing, the Tab mark dot, `<C-q>` → a new list, and the
-- severity filter bar for free; this file just sources the rows from `getqflist`/`getloclist` and styles them.
--
---@module "lvim-qf-loc.qf.browser"

local config = require("lvim-qf-loc.config")
local notify = require("lvim-qf-loc.utils.notify")

local M = {}

--- The browser's identity in the dock stack (`opts.key` of the picker it opens through).
local KEY = "lvim-qf-loc"

--- The raw list (quickfix or a window's location list) as browser items, drawn as the editable quickfix draws
--- its rows (qf/edit.lua): ` N │ [icon] file │ lnum, col │ source line` — the ordinal, the aligned filename and
--- position columns in the same colours, and the source line with its file's treesitter colours. A plain file
--- list is ` N │ path`; a position-less list with descriptions ` N │ file │ description`. A grep entry that
--- knows where its match ends (`end_col`) marks the match.
---@param loclist_win integer?  a window handle → that window's location list; nil → the quickfix list
---@return table[] items
local function build_items(loclist_win)
    local cols = require("lvim-qf-loc.qf.edit").columns
    local raw = loclist_win and vim.fn.getloclist(loclist_win, { items = 0 }).items
        or vim.fn.getqflist({ items = 0 }).items
    raw = raw or {}
    local positioned = require("lvim-qf-loc.qf.edit").list_positioned(raw)
    local files = cols.list_is_files(raw)
    local cap = config.edit.max_filename_width
    local sep = " " .. config.edit.separator .. " "

    -- the entries the browser shows: the real ones (context rows, valid = 0, belong to the editable window)
    local entries = {}
    for _, e in ipairs(raw) do
        local path = (e.bufnr and e.bufnr > 0 and vim.api.nvim_buf_is_valid(e.bufnr))
                and vim.api.nvim_buf_get_name(e.bufnr)
            or ""
        if path ~= "" and (e.valid ~= 0 or not positioned) then
            entries[#entries + 1] = { e = e, path = path }
        end
    end

    -- list-wide column widths, so every row lines up
    local ord_w, file_w, mid_w, sev_w = #tostring(math.max(1, #entries)), 0, 1, 0
    for _, x in ipairs(entries) do
        file_w = math.max(file_w, vim.fn.strdisplaywidth(cols.filename_of(x.e, cap)))
        mid_w = math.max(mid_w, vim.fn.strdisplaywidth(cols.mid_text(x.e)))
        sev_w = math.max(sev_w, vim.fn.strdisplaywidth(cols.icon_of(x.e)))
    end

    local cache = require("lvim-qf-loc.qf.filecache").new()
    local tcache = {}
    local items = {}
    for n, x in ipairs(entries) do
        local e = x.e
        local parts, spans = {}, {}
        local len = 0
        local function put(text, hl)
            parts[#parts + 1] = text
            if hl and #text > 0 then
                spans[#spans + 1] = { len, len + #text, hl }
            end
            len = len + #text
        end
        put(cols.lpad(tostring(n), ord_w), "LvimQfLocOrdinal")
        put(sep, "LvimQfLocSep")
        local body, body_hl
        if files then
            body, body_hl = cols.path_text(e), "LvimQfLocFile"
        elseif not positioned then
            put(cols.rpad(cols.filename_of(e, cap), file_w), "LvimQfLocFile")
            put(sep, "LvimQfLocSep")
            body = cols.description_text(e)
        else
            if sev_w > 0 then
                put(cols.rpad(cols.icon_of(e), sev_w), cols.sev_hl[e.type or ""] or "LvimQfLocSep")
            end
            put(cols.rpad(cols.filename_of(e, cap), file_w), "LvimQfLocFile")
            put(sep, "LvimQfLocSep")
            put(cols.lpad(cols.mid_text(e), mid_w), "LvimQfLocLnum")
            put(sep, "LvimQfLocSep")
            body = cols.source_text(e, cache)
        end
        body = (body or ""):gsub("[\r\n]+", " ")
        local locator = len
        put(body, body_hl)
        local match
        if positioned then
            if config.edit.syntax then
                for _, r in ipairs(cols.syntax_ranges(e, body, cols.ts_ctx(tcache, e.bufnr)) or {}) do
                    spans[#spans + 1] = { locator + r[1], locator + r[2], r[3] }
                end
            end
            -- the match a grep entry points at: col..end_col on its own line (1-based, end exclusive)
            local c0, c1 = (e.col or 0) - 1, (e.end_col or 0) - 1
            if c0 >= 0 and c1 > c0 and (e.end_lnum or 0) <= e.lnum and c1 <= #body then
                match = { { c0 = locator + c0, c1 = locator + c1 } }
            end
        end
        items[#items + 1] = {
            path = x.path,
            lnum = (e.lnum and e.lnum > 0) and e.lnum or 1,
            col = (e.col and e.col > 0) and e.col or 1,
            end_lnum = e.end_lnum,
            end_col = e.end_col,
            type = e.type or "",
            text = table.concat(parts),
            qf_text = e.text, -- the entry's own text, kept when the rows go back to a quickfix list (`<C-q>`)
            icon = "", -- the columns carry everything (no file icon, as in the editable list)
            hl_spans = spans,
            locator_bytes = locator,
            match_bytes = match,
        }
    end
    return items
end

--- Jump to an entry and centre it. `nvim_win_set_buf` (not `:edit`) so an unsaved editable preview can't block
--- the jump with E37.
---@param it table
local function jump(it)
    if not (it and it.path) then
        return
    end
    local buf = vim.fn.bufadd(it.path)
    local ok, err = pcall(vim.fn.bufload, buf)
    if not ok then
        vim.notify("lvim-qf-loc: cannot load " .. it.path .. ": " .. tostring(err), vim.log.levels.WARN)
        return
    end
    vim.api.nvim_win_set_buf(0, buf)
    vim.bo[buf].buflisted = true
    pcall(vim.api.nvim_win_set_cursor, 0, { it.lnum or 1, math.max(0, (it.col or 1) - 1) })
    vim.cmd("normal! zz")
end

--- Open the browser. `loclist_win` = a window handle for that window's location list, or nil for the quickfix
--- list. `layout` = "area" (default) | "float" | "bottom".
---@param loclist_win integer?
---@param layout string?
function M.open(loclist_win, layout)
    local ok, picker = pcall(require, "lvim-picker")
    if not ok then
        notify("lvim-picker is required for the browser.", vim.log.levels.WARN)
        return
    end
    local items = build_items(loclist_win)
    -- the grep a list came from (lvim-picker keeps it in the list's context): its matches are marked in the
    -- preview too
    local what = loclist_win and vim.fn.getloclist(loclist_win, { context = 0 }) or vim.fn.getqflist({ context = 0 })
    local grep = type(what.context) == "table" and type(what.context.lvim_picker) == "table" and what.context.lvim_picker
        or {}
    if #items == 0 then
        notify("List is empty.", vim.log.levels.INFO)
        return
    end

    picker.open({
        -- its own dock identity (else it is derived from the title, the same as lvim-picker's own quickfix
        -- finder), so `M.close` can find it
        key = KEY,
        title = loclist_win and "Location List" or "Quickfix",
        title_pos = config.title_pos, -- alignment — ONE config value for every layout ("center" default)
        layout = layout or config.browser.layout,
        -- Forward OUR dock config to the picker per-call: `dock_stack` decides managed-stack vs. standalone, and
        -- `force` supplies the per-layout ANCHORED geometry overrides (deep-merged over the central dock geometry
        -- inside `dock.slot`). Both apply ONLY to this picker-based browser — the native qf window and the
        -- cursor-preview float stay content-fit and are untouched.
        dock_stack = config.dock.dock_stack,
        force = config.dock.force,
        items = items,
        format = function(it)
            return it.text
        end,
        preview_file = true, -- the REAL file buffer in the preview — no FFI, no internal scroll math
        match_pattern = type(grep.pattern) == "string" and grep.pattern or nil,
        regex = grep.regex == true,
        preview_side = config.browser.preview_side, -- "right" (default) | "left" | "dynamic" (peek float above)
        -- No `preview_heights`: the SLOT height of the picker's float/area/bottom dock is centralized by
        -- lvim-utils (`config.dock.geometry`). Passing our own would duplicate it, so we let the picker/surface
        -- derive it — this browser only chooses the layout and the preview SIDE, never the size.
        keys = (config.switch and config.switch ~= "") and {
            {
                key = config.switch,
                name = "native",
                run = function(_, close)
                    require("lvim-qf-loc.qf.view").switch(loclist_win, close)
                end,
            },
        } or nil,
        subtitle = function(it)
            return vim.fn.fnamemodify(it.path, ":t")
        end,
        on_confirm = jump,
    })
end

--- Close the browser if it is open (the view switch, run as a command while it shows).
function M.close()
    local okd, dock = pcall(require, "lvim-utils.dock")
    if okd and type(dock.entries) == "function" then
        for _, e in ipairs(dock.entries()) do
            if e.id == "lvim-picker:" .. KEY then
                dock.close(e.key)
            end
        end
    end
    local oks, source = pcall(require, "lvim-picker.source")
    if oks and type(source.close_active) == "function" then
        source.close_active() -- an un-docked open
    end
end

M._build_items = build_items -- internal test seam

return M
