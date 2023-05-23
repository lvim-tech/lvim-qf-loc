local config = require("lvim-qf-loc.config")
local diagnostics = require("lvim-qf-loc.diagnostics")

local group = vim.api.nvim_create_augroup("Lvimqfloc", {
    clear = false,
})

local M = {}

local qf_height = function(minheight, maxheight)
    local height = math.max(math.min(vim.fn.line("$"), maxheight), minheight)
    vim.cmd(height .. "wincmd _")
end

M.init = function()
    vim.api.nvim_create_autocmd({
        "DiagnosticChanged",
        "DirChanged",
    }, {
        callback = function()
            diagnostics.diagnostics_reload()
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
    vim.api.nvim_create_autocmd("FileType", {
        pattern = "qf",
        callback = function()
            qf_height(config.min_height, config.max_height)
        end,
        group = group,
    })
end

return M
