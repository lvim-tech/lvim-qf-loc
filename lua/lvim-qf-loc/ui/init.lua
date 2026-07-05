-- lua/lvim-qf-loc/ui/init.lua
-- Lazily-built, shared lvim-utils UI instance for the management popup. `get()` constructs it once from
-- `config.popup_global` and caches it; `reset()` drops the cache so the next `get()` rebuilds against the
-- current config (setup() calls it after merging user overrides). Returns nil when lvim-utils is absent, so
-- callers can fall back gracefully.
--
---@module "lvim-qf-loc.ui"

local config = require("lvim-qf-loc.config")

local M = {}

---@type table?  the cached lvim-utils UI instance (nil until built / after reset)
local instance = nil

--- The shared lvim-utils UI instance, built on first use from `config.popup_global`. nil when lvim-utils is
--- not installed.
---@return table?  the UI instance, or nil
function M.get()
    if instance then
        return instance
    end
    local ok, mod = pcall(require, "lvim-ui")
    if not ok then
        return nil
    end
    instance = mod.new(config.popup_global)
    return instance
end

--- Drop the cached instance so the next get() rebuilds it (after a config merge).
---@return nil
function M.reset()
    instance = nil
end

return M
