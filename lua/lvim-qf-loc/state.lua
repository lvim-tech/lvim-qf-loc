-- lua/lvim-qf-loc/state.lua
-- Runtime STATE for the plugin — never configuration. config.lua holds only the user-tunable defaults (merged
-- in place by setup); anything the plugin flips at runtime lives here instead, so the config table stays a pure
-- description of intent. Currently the single flag tracks whether the "Diagnostics" quickfix list is the live
-- one being kept fresh by the DiagnosticChanged / DirChanged autocmd.
--
---@module "lvim-qf-loc.state"

---@class LvimQfLocState
---@field is_active boolean  Whether the diagnostics-backed "Diagnostics" quickfix list is currently active.
local M = {
    is_active = false,
}

return M
