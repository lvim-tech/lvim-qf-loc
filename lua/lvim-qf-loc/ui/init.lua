-- Lazily-initialised shared lvim-utils UI instance.
-- Returns nil when lvim-utils is not installed so callers can fall back.

local _instance = nil

local function get()
    if _instance then
        return _instance
    end
    local ok, mod = pcall(require, "lvim-utils.ui")
    if not ok then
        return nil
    end
    local cfg = require("lvim-qf-loc.config").popup_global
    _instance = mod.new(cfg)
    return _instance
end

local function reset()
    _instance = nil
end

return { get = get, reset = reset }
