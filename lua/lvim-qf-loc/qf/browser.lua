-- lua/lvim-qf-loc/qf/browser.lua
-- The quickfix / location-list BROWSER — the bqf-style experience (a live preview of the entry under the
-- cursor) reimplemented on the lvim-utils stack: the list + a REAL-Neovim preview open in OUR area (the
-- surface chassis, same zone as the pickers and the lsp navigation), NOT a native qf float and NOT bqf's
-- FFI + "magicwin" window math (the brittle, crash-prone parts we deliberately drop). The list is the
-- lvim-utils.picker list — so it comes with fuzzy narrowing, the Tab mark dot, `<C-q>` → a new list, and the
-- severity filter bar for free; this file just sources the rows from `getqflist`/`getloclist` and styles them.
--
---@module "lvim-qf-loc.qf.browser"

local config = require("lvim-qf-loc.config")

local M = {}

--- The quickfix entry `type` field → its severity icon + highlight (diagnostic-sourced lists carry it; plain
--- lists, e.g. grep, have "" and fall back to a neutral glyph).
---@param t string  the entry `type` ("E"/"W"/"I"/"N"/"H"/"")
---@return string icon, string hl
local function severity(t)
    local map = config.browser.icons
    local hl = ({
        E = "DiagnosticError",
        W = "DiagnosticWarn",
        I = "DiagnosticInfo",
        N = "DiagnosticHint",
        H = "DiagnosticHint",
    })[t]
    return map[t] or map.default, hl or "Special"
end

--- The raw list (quickfix or a window's location list) + whether it currently looks diagnostic-sourced.
---@param loclist_win integer?  a window handle → that window's location list; nil → the quickfix list
---@return table[] items, boolean has_severity
local function build_items(loclist_win)
    local raw = loclist_win and vim.fn.getloclist(loclist_win, { items = 0, idx = 0 }).items
        or vim.fn.getqflist({ items = 0 }).items
    local items, has_severity = {}, false
    for _, e in ipairs(raw or {}) do
        local path = (e.bufnr and e.bufnr > 0 and vim.api.nvim_buf_is_valid(e.bufnr))
                and vim.api.nvim_buf_get_name(e.bufnr)
            or ""
        if path ~= "" then
            local icon, icon_hl = severity(e.type or "")
            if (e.type or "") ~= "" then
                has_severity = true
            end
            local short = vim.fn.fnamemodify(path, ":~:.")
            local msg = (e.text or ""):gsub("^%s+", ""):gsub("[\r\n]+", " ")
            items[#items + 1] = {
                path = path,
                lnum = (e.lnum and e.lnum > 0) and e.lnum or 1,
                col = (e.col and e.col > 0) and e.col or 1,
                end_lnum = e.end_lnum,
                end_col = e.end_col,
                type = e.type or "",
                text = ("%s:%d  %s"):format(short, e.lnum or 0, msg),
                icon = icon,
                icon_hl = icon_hl,
            }
        end
    end
    return items, has_severity
end

--- Jump to an entry and centre it. `nvim_win_set_buf` (not `:edit`) so an unsaved editable preview can't block
--- the jump with E37.
---@param it table
local function jump(it)
    if not (it and it.path) then
        return
    end
    local buf = vim.fn.bufadd(it.path)
    vim.fn.bufload(buf)
    vim.api.nvim_win_set_buf(0, buf)
    pcall(vim.api.nvim_win_set_cursor, 0, { it.lnum or 1, math.max(0, (it.col or 1) - 1) })
    vim.cmd("normal! zz")
end

--- A severity filter button for the header bar (keeps only entries of `t`).
---@param id string
---@param label string
---@param t string
---@param key string
---@return table
local function severity_button(id, label, t, key)
    return {
        id = id,
        label = label,
        key = key,
        predicate = function(it)
            return it.type == t
        end,
    }
end

--- Open the browser. `loclist_win` = a window handle for that window's location list, or nil for the quickfix
--- list. `layout` = "area" (default) | "float" | "bottom".
---@param loclist_win integer?
---@param layout string?
function M.open(loclist_win, layout)
    local ok, picker = pcall(require, "lvim-utils.picker")
    if not ok then
        require("lvim-qf-loc.utils.notify")("lvim-utils is required for the browser.", vim.log.levels.WARN)
        return
    end
    local items, has_severity = build_items(loclist_win)
    if #items == 0 then
        require("lvim-qf-loc.utils.notify")("List is empty.", vim.log.levels.INFO)
        return
    end

    -- the severity filter bar only when the list actually carries severities (diagnostic-sourced)
    local filters
    if has_severity then
        filters = {
            {
                id = "severity",
                active = "all",
                buttons = {
                    { id = "all", label = "All", key = "a" },
                    severity_button("error", "Error", "E", "e"),
                    severity_button("warn", "Warn", "W", "w"),
                    severity_button("info", "Info", "I", "i"),
                    severity_button("hint", "Hint", "H", "n"),
                },
            },
        }
    end

    picker.open({
        title = loclist_win and "Location List" or "Quickfix",
        layout = layout or config.browser.layout,
        items = items,
        format = function(it)
            return it.text
        end,
        preview_file = true, -- the REAL file buffer in the preview (the bqf feature) — no FFI / magicwin
        subtitle = function(it)
            return vim.fn.fnamemodify(it.path, ":t")
        end,
        on_confirm = jump,
        filters = filters,
    })
end

return M
