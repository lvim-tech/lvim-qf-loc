-- lua/lvim-qf-loc/utils/notify.lua
-- The plugin's single notification channel. Honours `config.notify` (a global mute), ignores empty messages,
-- and normalises the level argument (a `vim.log.levels.*` number, a level NAME string, or nil → INFO) before
-- scheduling `vim.notify` off the current callback — safe to call from autocmds / fast-event contexts.
--
---@module "lvim-qf-loc.utils.notify"

local config = require("lvim-qf-loc.config")

--- Resolve a level argument to a `vim.log.levels` number. Accepts a number (passed through), a level NAME
--- ("ERROR"/"WARN"/…, case-insensitive), or nil → INFO.
---@param level string|integer|nil
---@return integer
local function to_level(level)
    if type(level) == "number" then
        return level
    end
    if type(level) == "string" then
        return vim.log.levels[level:upper()] or vim.log.levels.INFO
    end
    return vim.log.levels.INFO
end

--- Emit a plugin notification (unless `config.notify` is false or `msg` is empty).
---@param msg string
---@param level string|integer|nil
---@return nil
return function(msg, level)
    if not config.notify then
        return
    end

    if type(msg) ~= "string" or msg == "" then
        return
    end

    local level_num = to_level(level)

    vim.schedule(function()
        pcall(vim.notify, msg, level_num, { title = "LVIM LIST" })
    end)
end
