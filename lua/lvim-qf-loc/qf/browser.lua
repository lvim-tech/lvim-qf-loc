-- lua/lvim-qf-loc/qf/browser.lua
-- The quickfix / location-list BROWSER — the bqf-style experience (a live preview of the entry under the
-- cursor) reimplemented on the lvim-utils stack: the list + a REAL-Neovim preview open in OUR area (the
-- surface chassis, same zone as the pickers and the lsp navigation), NOT a native qf float and NOT bqf's
-- FFI + "magicwin" window math (the brittle, crash-prone parts we deliberately drop). The list is the
-- lvim-picker list — so it comes with fuzzy narrowing, the Tab mark dot, `<C-q>` → a new list, and the
-- severity filter bar for free; this file just sources the rows from `getqflist`/`getloclist` and styles them.
--
---@module "lvim-qf-loc.qf.browser"

local config = require("lvim-qf-loc.config")
local notify = require("lvim-qf-loc.utils.notify")

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

--- The raw list (quickfix or a window's location list) as browser items.
---@param loclist_win integer?  a window handle → that window's location list; nil → the quickfix list
---@return table[] items
local function build_items(loclist_win)
    local raw = loclist_win and vim.fn.getloclist(loclist_win, { items = 0, idx = 0 }).items
        or vim.fn.getqflist({ items = 0 }).items
    local items = {}
    for _, e in ipairs(raw or {}) do
        local path = (e.bufnr and e.bufnr > 0 and vim.api.nvim_buf_is_valid(e.bufnr))
                and vim.api.nvim_buf_get_name(e.bufnr)
            or ""
        if path ~= "" then
            local icon, icon_hl = severity(e.type or "")
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
    if #items == 0 then
        notify("List is empty.", vim.log.levels.INFO)
        return
    end

    picker.open({
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
        preview_file = true, -- the REAL file buffer in the preview (the bqf feature) — no FFI / magicwin
        preview_side = config.browser.preview_side, -- "above" → preview on top, list full-width below
        -- No `preview_heights`: the SLOT height of the picker's float/area/bottom dock is centralized by
        -- lvim-utils (`config.dock.geometry`). Passing our own would duplicate it, so we let the picker/surface
        -- derive it — this browser only chooses the layout and the preview SIDE, never the size.
        subtitle = function(it)
            return vim.fn.fnamemodify(it.path, ":t")
        end,
        on_confirm = jump,
    })
end

return M
