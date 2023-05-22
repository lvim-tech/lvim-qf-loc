local utils = require("lvim-qf-loc.utils")
local config = require("lvim-qf-loc.config")

local M = {}

config.is_active = false

local function compare_by_severity(a, b)
    local severities = { E = 1, W = 2, I = 3, N = 4 }
    return severities[a.type] < severities[b.type]
end

M.diagnostics_reload = function()
    local len = utils.length("quick_fix")
    for i = 1, len do
        local title = utils.title("quick_fix", i)
        if title == "Diagnostics" then
            local diags = vim.diagnostic.get()
            local qfdiags = vim.diagnostic.toqflist(diags)
            table.sort(qfdiags, compare_by_severity)
            local qflist = vim.fn.getqflist({ nr = i, all = 1 })
            qflist["nr"] = i
            qflist["title"] = "Diagnostics"
            qflist.items = qfdiags
            vim.fn.setqflist({}, "r", qflist)
            return
        end
    end
end

M.qf_diagnostics = function()
    if config.is_active == false then
        config.is_active = true
        vim.diagnostic.setqflist()
        M.diagnostics_reload()
    else
        local len = utils.length("quick_fix")
        local nr = 0
        for i = 1, len do
            local title = utils.title("quick_fix", i)
            if title == "Diagnostics" then
                nr = i
            end
        end
        local current_nr = utils.current("quick_fix")
        local diff = nr - current_nr
        if diff > 0 then
            for _ = 0, diff do
                vim.cmd("silent cnewer")
            end
        elseif diff < 0 then
            for _ = 0, -diff do
                vim.cmd("silent colder")
            end
        end
        vim.cmd("silent copen")
    end
end

return M
