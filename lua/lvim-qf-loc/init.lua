local config = require("lvim-qf-loc.config")
local autocmds = require("lvim-qf-loc.hooks.autocmds")
local commands = require("lvim-qf-loc.hooks.commands")

local M = {}

M.setup = function(user_config)
    if user_config ~= nil then
        -- merge IN PLACE into the live config table (config.lua is the single source of truth): every module
        -- does `require("lvim-qf-loc.config")` and gets THIS table, so user overrides must mutate it, not
        -- replace the local. Use the shared lvim-utils merge (array-replace) when present, else an equivalent.
        local ok, utils = pcall(require, "lvim-utils.utils")
        if ok and type(utils.merge) == "function" then
            utils.merge(config, user_config)
        else
            local function merge(target, opts)
                for k, v in pairs(opts or {}) do
                    if type(v) == "table" and type(target[k]) == "table" and not vim.islist(v) then
                        merge(target[k], v)
                    else
                        target[k] = v
                    end
                end
            end
            merge(config, user_config)
        end
        require("lvim-qf-loc.ui").reset()
    end
    -- bring in Neovim's built-in `:Cfilter` / `:Lfilter` (an opt plugin, not auto-loaded) — a natural companion
    -- to the quickfix UI; idempotent + guarded so a missing runtime never breaks setup
    if config.cfilter then
        pcall(vim.cmd.packadd, "cfilter")
    end
    commands.setup()
    autocmds.init()
    require("lvim-qf-loc.qf.edit").setup() -- the editable quickfix (quickfixtextfunc + the FileType qf hook)
    require("lvim-qf-loc.qf.preview").setup() -- the preview footer highlights (themed, survive colorscheme)
end

return M
