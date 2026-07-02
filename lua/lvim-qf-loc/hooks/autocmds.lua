-- lua/lvim-qf-loc/hooks/autocmds.lua
-- The plugin's autocommands, all under one augroup:
--   • DiagnosticChanged / DirChanged → keep the live "Diagnostics" quickfix list fresh (diagnostics_reload).
--   • ExitPre / QuitPre             → tear down the diagnostics watcher so it can't fire mid-shutdown (when the
--                                     diagnostic subsystem is being dismantled and a reload would error).
--   • FileType qf                   → size the quickfix window to fit its entries (min..max height).
--
---@module "lvim-qf-loc.hooks.autocmds"

local config = require("lvim-qf-loc.config")
local diagnostics = require("lvim-qf-loc.core.diagnostics")

local group = vim.api.nvim_create_augroup("Lvimqfloc", {
    clear = false,
})

local M = {}

--- Size the quickfix window to fit its content, clamped to `[minheight, maxheight]`. The native editable view
--- adds a top winbar that eats one row, so reserve it — otherwise the last entry falls below the fold even
--- though the height was meant to fit them all.
---@param minheight integer
---@param maxheight integer
---@return nil
local function qf_height(minheight, maxheight)
    local height = math.max(math.min(vim.fn.line("$"), maxheight), minheight)
    if config.view == "native" and config.edit.enabled then
        height = height + 1
    end
    vim.cmd(height .. "wincmd _")
end

--- Register the plugin's autocommands (idempotent within the shared augroup).
---@return nil
M.init = function()
    -- Keep the live "Diagnostics" quickfix list in sync with the diagnostics. Its id is captured so shutdown
    -- can delete EXACTLY this autocmd (never guessing an index in the group).
    local diag_id = vim.api.nvim_create_autocmd({
        "DiagnosticChanged",
        "DirChanged",
    }, {
        callback = function()
            diagnostics.diagnostics_reload()
        end,
        group = group,
    })
    -- On shutdown, remove the diagnostics watcher so a DiagnosticChanged fired while the diagnostic subsystem is
    -- being torn down cannot trigger a reload against half-dismantled state.
    vim.api.nvim_create_autocmd({
        "ExitPre",
        "QuitPre",
    }, {
        callback = function()
            pcall(vim.api.nvim_del_autocmd, diag_id)
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
