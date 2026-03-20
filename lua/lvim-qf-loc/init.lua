local config = require("lvim-qf-loc.config")
local autocmds = require("lvim-qf-loc.hooks.autocmds")
local commands = require("lvim-qf-loc.hooks.commands")

local M = {}

M.setup = function(user_config)
    if user_config ~= nil then
        config = vim.tbl_deep_extend("force", config, user_config)
        require("lvim-qf-loc.ui").reset()
    end
    commands.setup()
    autocmds.init()
end

return M
