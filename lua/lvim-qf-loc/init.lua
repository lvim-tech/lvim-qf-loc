-- lua/lvim-qf-loc/init.lua
-- The plugin entry point. `setup()` merges user options into the live config (in place, via the shared
-- lvim-utils merge), pulls in Neovim's built-in `:Cfilter`/`:Lfilter` when enabled, registers the
-- `:LvimQf`/`:LvimLoc` commands and the diagnostics / height autocmds, and wires the editable quickfix +
-- preview. Every module reads `require("lvim-qf-loc.config")`, so the in-place merge is what makes user
-- overrides visible everywhere.
--
---@module "lvim-qf-loc"

local config = require("lvim-qf-loc.config")
local autocmds = require("lvim-qf-loc.hooks.autocmds")
local commands = require("lvim-qf-loc.hooks.commands")
local ui = require("lvim-qf-loc.ui")
local edit = require("lvim-qf-loc.qf.edit")
local preview = require("lvim-qf-loc.qf.preview")

local M = {}

--- Configure and activate the plugin.
---@param user_config LvimQfLocConfig?  User overrides, merged into the live config in place.
---@return nil
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
        ui.reset()
    end
    -- bring in Neovim's built-in `:Cfilter` / `:Lfilter` (an opt plugin, not auto-loaded) — a natural companion
    -- to the quickfix UI; idempotent + guarded so a missing runtime never breaks setup
    if config.cfilter then
        pcall(vim.cmd.packadd, "cfilter")
    end
    commands.setup()
    autocmds.init()
    edit.setup() -- the editable quickfix (quickfixtextfunc + the FileType qf hook)
    preview.setup() -- the preview footer highlights (themed, survive colorscheme)
end

return M
