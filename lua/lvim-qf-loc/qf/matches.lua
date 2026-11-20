-- lua/lvim-qf-loc/qf/matches.lua
-- The search a list came from, marked where the list is shown. A grep list from lvim-picker keeps its pattern
-- in the list's `context` (`{ lvim_picker = { pattern, regex } }`); a `:vimgrep` list names its pattern in its
-- title. The marks are `matchadd`s — WINDOW-local, so the real file buffers a preview shows never carry them
-- into another window of the same file.
--
---@module "lvim-qf-loc.qf.matches"

local M = {}

--- The search pattern of the list `qwin` shows (a quickfix or a location list window) as a Vim regex, or nil.
---@param qwin integer
---@return string?
function M.pattern(qwin)
    local info = vim.fn.getwininfo(qwin)[1]
    local what = (info and info.loclist == 1) and vim.fn.getloclist(qwin, { context = 0, title = 0 })
        or vim.fn.getqflist({ context = 0, title = 0 })
    local ctx = type(what.context) == "table" and what.context.lvim_picker
    if type(ctx) == "table" and type(ctx.pattern) == "string" and ctx.pattern ~= "" then
        local case = ctx.pattern:find("%u") and "\\C" or "\\c" -- ripgrep's --smart-case
        if ctx.regex then
            return case .. ctx.pattern
        end
        return case .. "\\V" .. vim.fn.escape(ctx.pattern, "\\")
    end
    -- `:vimgrep /pat/ files` (or `:vimgrep pat files`): already a Vim regex
    -- (past any modifiers in front: `:silent vimgrep …`, `:noautocmd vimgrep …`)
    local cmd = (what.title or ""):match("^:%s*(.*)$")
    if not cmd then
        return nil
    end
    while not cmd:match("^vimg") and cmd:match("^%a+!?%s+") do
        cmd = cmd:gsub("^%a+!?%s+", "", 1)
    end
    local args = cmd:match("^vimg[%a]*!?%s+(.*)$")
    if not args then
        return nil
    end
    local delim, pat = args:match("^([^%w%s])(.-)%1")
    if delim and pat ~= "" then
        return pat
    end
    return args:match("^(%S+)")
end

--- Mark `pattern` in `win` (every match), and `focus` (`{ lnum, col, end_col }`, 1-based, end exclusive)
--- harder; replaces this module's earlier marks in that window. A nil pattern / focus only clears.
---@param win integer
---@param pattern string?
---@param focus? { lnum: integer, col: integer, end_col: integer, end_lnum?: integer }
function M.mark(win, pattern, focus)
    if not vim.api.nvim_win_is_valid(win) then
        return
    end
    for _, id in ipairs(vim.w[win].lvim_qf_matches or {}) do
        pcall(vim.fn.matchdelete, id, win)
    end
    local ids = {}
    if pattern and pattern ~= "" then
        local ok, id = pcall(vim.fn.matchadd, "LvimQfLocMatch", pattern, 250, -1, { window = win })
        if ok and id > 0 then
            ids[#ids + 1] = id
        end
    end
    if focus and focus.lnum and (focus.col or 0) > 0 and (focus.end_col or 0) > focus.col then
        if (focus.end_lnum or 0) == 0 or focus.end_lnum == focus.lnum then
            local ok, id = pcall(
                vim.fn.matchaddpos,
                "LvimQfLocMatchFocus",
                { { focus.lnum, focus.col, focus.end_col - focus.col } },
                260,
                -1,
                { window = win }
            )
            if ok and id > 0 then
                ids[#ids + 1] = id
            end
        end
    end
    vim.w[win].lvim_qf_matches = ids
end

local NS = vim.api.nvim_create_namespace("lvim-qf-loc-list-match")

--- Mark the matches in the LIST buffer `buf` (the native quickfix buffer — the plugin's own, so a buffer mark
--- leaks nowhere): each entry's OWN match (`col`..`end_col` on its line — what a grep found, the browser marks
--- the same span; a row's text is its source line, so the columns map 1:1), and every match of `pattern` (the
--- search the list came from, when it is known). Extmarks over the rows' syntax, not a `matchadd`: the rows
--- carry their source's treesitter colours as extmarks. Re-run to refresh; nil/empty input only clears.
---@param buf integer
---@param pattern string?
---@param items table[]?  the list's entries, in row order
function M.mark_list(buf, pattern, items)
    if not vim.api.nvim_buf_is_valid(buf) then
        return
    end
    vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local function put(row, c0, c1)
        pcall(vim.api.nvim_buf_set_extmark, buf, NS, row, c0, {
            end_col = c1,
            hl_group = "LvimQfLocMatch",
            priority = 200, -- over the rows' syntax (90)
        })
    end
    for i, e in ipairs(items or {}) do
        local line = lines[i]
        local c0, c1 = (e.col or 0) - 1, (e.end_col or 0) - 1
        if line and e.valid ~= 0 and c0 >= 0 and c1 > c0 and c1 <= #line and ((e.end_lnum or 0) <= e.lnum) then
            put(i - 1, c0, c1)
        end
    end
    local ok, re = pcall(vim.regex, pattern or "")
    if not (ok and re and pattern and pattern ~= "") then
        return
    end
    for i, line in ipairs(lines) do
        local from = 0
        while from < #line do
            local s0, e0 = re:match_str(line:sub(from + 1))
            if not s0 then
                break
            end
            if e0 > s0 then
                put(i - 1, from + s0, from + e0)
            end
            from = from + math.max(e0, s0 + 1)
        end
    end
end

--- The match colours: the lvim-ui ones (the same as a grep in the picker), plain fallbacks without it.
function M.define_highlights()
    local ui = not vim.tbl_isempty(vim.api.nvim_get_hl(0, { name = "LvimUiMsgAreaMatch" }))
    vim.api.nvim_set_hl(0, "LvimQfLocMatch", { link = ui and "LvimUiMsgAreaMatch" or "Search" })
    vim.api.nvim_set_hl(0, "LvimQfLocMatchFocus", { link = ui and "LvimUiPeekTitle" or "IncSearch" })
end

return M
