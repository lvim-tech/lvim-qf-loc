local utils = require("lvim-qf-loc.utils")
local config = require("lvim-qf-loc.config")
local notify = require("lvim-ui-config.notify")

local M = {}

config.is_active = false

local group = vim.api.nvim_create_augroup("Lvimqfloc", {
    clear = false,
})

local diagnostics_reload = function()
    local len = utils.length("quick_fix")
    for i = 1, len do
        local title = utils.title("quick_fix", i)
        if title == "Diagnostics" then
            local diags = vim.diagnostic.get()
            local qfdiags = vim.diagnostic.toqflist(diags)
            local qflist = vim.fn.getqflist({ nr = i, all = 1 })
            qflist["nr"] = i
            qflist["title"] = "Diagnostics"
            qflist.items = qfdiags
            vim.fn.setqflist({}, "r", qflist)
            return
        end
    end
end

M.init = function()
    vim.api.nvim_create_autocmd({
        "DiagnosticChanged",
        "DirChanged",
    }, {
        callback = function()
            diagnostics_reload()
        end,
        group = group,
    })
    vim.api.nvim_create_autocmd({
        "ExitPre",
        "QuitPre",
    }, {
        callback = function()
            local autocommands = vim.api.nvim_get_autocmds({
                group = group,
            })
            vim.api.nvim_del_autocmd(autocommands[1]["id"])
        end,
        group = group,
    })
end

M.qf_diagnostics = function()
    if config.is_active == false then
        config.is_active = true
        vim.diagnostic.setqflist()
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
