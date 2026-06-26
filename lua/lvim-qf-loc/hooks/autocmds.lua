local config = require("lvim-qf-loc.config")
local diagnostics = require("lvim-qf-loc.core.diagnostics")

local group = vim.api.nvim_create_augroup("Lvimqfloc", {
    clear = false,
})

local M = {}

local qf_height = function(minheight, maxheight)
    local height = math.max(math.min(vim.fn.line("$"), maxheight), minheight)
    -- the native editable view adds a top winbar that consumes one window row, so reserve it — otherwise the
    -- last entry is pushed below the fold and needs scrolling even though the height was meant to fit them all
    if config.view == "native" and config.edit.enabled then
        height = height + 1
    end
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
