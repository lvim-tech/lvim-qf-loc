-- lua/lvim-qf-loc/qf/history.lua
-- A picker over the quickfix / location HISTORY — Neovim keeps the last lists (`:colder`/`:cnewer`), this
-- shows them all at once (title + entry count, the current one marked) and jumps to the chosen one. Built on
-- the lvim-utils picker, in our area. Switching is done with relative `:colder`/`:cnewer` (there is no absolute
-- "go to list N"), computed from the current list number.
--
---@module "lvim-qf-loc.qf.history"

local M = {}

--- Read the history of a window's location list (loclist_win) or the quickfix list (nil): one item per stored
--- list, newest kept by vim, plus which one is current.
---@param loclist_win integer?
---@return table[] items, integer current, integer count
local function history(loclist_win)
    local get = function(what)
        return loclist_win and vim.fn.getloclist(loclist_win, what) or vim.fn.getqflist(what)
    end
    local count = get({ nr = "$" }).nr or 0
    local current = get({ nr = 0 }).nr or 0
    local items = {}
    for i = 1, count do
        local info = get({ nr = i, title = 1, size = 1 })
        local title = (info.title and info.title ~= "") and info.title or "(no title)"
        items[#items + 1] = {
            nr = i,
            text = ("%s%d. %s  (%d)"):format(i == current and "➤ " or "  ", i, title, info.size or 0),
        }
    end
    return items, current, count
end

--- Open the history picker; confirming switches to that list and opens it.
---@param loclist_win integer?
---@param layout string?
function M.open(loclist_win, layout)
    local ok, picker = pcall(require, "lvim-utils.picker")
    if not ok then
        require("lvim-qf-loc.utils.notify")("lvim-utils is required for the history picker.", vim.log.levels.WARN)
        return
    end
    local items, current = history(loclist_win)
    if #items == 0 then
        require("lvim-qf-loc.utils.notify")("No history.", vim.log.levels.INFO)
        return
    end
    -- show newest first
    local rev = {}
    for i = #items, 1, -1 do
        rev[#rev + 1] = items[i]
    end
    picker.open({
        title = loclist_win and "Location History" or "Quickfix History",
        layout = layout or require("lvim-qf-loc.config").browser.layout,
        items = rev,
        format = function(it)
            return it.text
        end,
        on_confirm = function(it)
            if not (it and it.nr) then
                return
            end
            local delta = it.nr - current
            if delta ~= 0 then
                -- relative navigation: cnewer for a higher number, colder for a lower one
                local cmd = loclist_win and (delta > 0 and "lnewer" or "lolder") or (delta > 0 and "cnewer" or "colder")
                pcall(vim.cmd, ("silent %d%s"):format(math.abs(delta), cmd))
            end
            pcall(vim.cmd, loclist_win and "lopen" or "copen")
        end,
    })
end

return M
