-- lua/lvim-qf-loc/core/diagnostics.lua
-- The diagnostics → quickfix bridge. `qf_diagnostics` (the `:LvimQf diagnostics` command) loads every workspace
-- diagnostic into a single "Diagnostics" quickfix list, severity-sorted, then opens the live-preview browser on
-- it — or notifies when there are no diagnostics. `diagnostics_reload` (driven by the DiagnosticChanged /
-- DirChanged autocmd) keeps that one list fresh as the diagnostics change.
--
---@module "lvim-qf-loc.core.diagnostics"

local utils = require("lvim-qf-loc.utils")
local state = require("lvim-qf-loc.state")
local browser = require("lvim-qf-loc.qf.browser")

local M = {}

state.is_active = false

--- Sort comparator: errors before warnings before info before notes (unknown types last).
---@param a table
---@param b table
---@return boolean
local function compare_by_severity(a, b)
    local severities = { E = 1, W = 2, I = 3, N = 4 }
    return (severities[a.type] or 5) < (severities[b.type] or 5)
end

--- Refresh the existing "Diagnostics" quickfix list (if any) with the current diagnostics — in place, so its
--- list number / position are preserved. Called from the DiagnosticChanged / DirChanged autocmd.
M.diagnostics_reload = function()
    local len = utils.length("quick_fix")
    for i = 1, len do
        if utils.title("quick_fix", i) == "Diagnostics" then
            local qfdiags = vim.diagnostic.toqflist(vim.diagnostic.get())
            table.sort(qfdiags, compare_by_severity)
            local qflist = vim.fn.getqflist({ nr = i, all = 1 })
            qflist.nr = i
            qflist.title = "Diagnostics"
            qflist.items = qfdiags
            vim.fn.setqflist({}, "r", qflist)
            return
        end
    end
end

--- Load every diagnostic into the "Diagnostics" quickfix list and open the browser on it; notify when there are
--- none. Reuses the single "Diagnostics" list (the autocmd keeps it fresh) and makes it current, else creates it.
M.qf_diagnostics = function()
    if vim.tbl_isempty(vim.diagnostic.get()) then
        utils.notify("No diagnostics")
        return
    end
    local items = vim.diagnostic.toqflist(vim.diagnostic.get())
    table.sort(items, compare_by_severity)

    local nr = 0
    for i = 1, utils.length("quick_fix") do
        if utils.title("quick_fix", i) == "Diagnostics" then
            nr = i
            break
        end
    end
    if nr > 0 then
        -- replace the existing list in place, then make it the current one so the browser shows it
        vim.fn.setqflist({}, "r", { nr = nr, title = "Diagnostics", items = items })
        local diff = nr - utils.current("quick_fix")
        for _ = 1, diff do
            vim.cmd("silent cnewer")
        end
        for _ = 1, -diff do
            vim.cmd("silent colder")
        end
    else
        vim.fn.setqflist({}, " ", { title = "Diagnostics", items = items }) -- a new list becomes current
    end
    state.is_active = true
    browser.open(nil)
end

return M
