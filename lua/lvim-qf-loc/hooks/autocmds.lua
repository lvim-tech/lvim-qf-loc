-- lua/lvim-qf-loc/hooks/autocmds.lua
-- The plugin's autocommands, all under one augroup:
--   • DiagnosticChanged / DirChanged → keep the live "Diagnostics" quickfix list fresh (diagnostics_reload).
--   • ExitPre                       → tear down the diagnostics watcher so it can't fire mid-shutdown (when the
--                                     diagnostic subsystem is being dismantled and a reload would error).
--   • FileType qf                   → size the quickfix window to fit its entries (min..max height).
--
---@module "lvim-qf-loc.hooks.autocmds"

local config = require("lvim-qf-loc.config")
local diagnostics = require("lvim-qf-loc.core.diagnostics")

local M = {}

--- The quickfix window's height cap, and whether it fits its content under it — so the native window shows as
--- many ENTRIES as the area browser does under the same settings (the Control Center's "Area height" / "Area
--- height auto"). The browser fills the AREA slot of the central dock geometry (lvim-utils `dock.slot("area")`),
--- but spends rows of it on its chrome (title, query, list bar, footer — `browser.chrome_rows()`); the native
--- window's only chrome is its button band. So the cap is the slot less the browser's chrome, plus the band.
--- Without lvim-utils: `config.max_height`, fitted.
---@return integer cap, boolean fit
local function height_cap()
    local ok, dock = pcall(require, "lvim-utils.dock")
    if ok and type(dock.slot) == "function" then
        local ok_s, slot = pcall(dock.slot, "area")
        if ok_s and type(slot) == "table" and (slot.height or 0) > 0 then
            local band = (config.view == "native" and config.edit.enabled) and 1 or 0
            local rows = slot.height - require("lvim-qf-loc.qf.browser").chrome_rows()
            return math.max(1, rows) + band, slot.height_auto ~= false
        end
    end
    return config.max_height, true
end

--- Size the quickfix window: its content (plus the native editable view's top winbar row, which would
--- otherwise push the last entry below the fold), clamped to `[minheight, cap]`, or the whole cap when the
--- geometry does not fit to content.
---@param minheight integer
---@return nil
local function qf_height(minheight)
    local cap, fit = height_cap()
    local height = cap
    if fit then
        height = vim.fn.line("$")
        if config.view == "native" and config.edit.enabled then
            height = height + 1
        end
        height = math.min(height, cap)
    end
    vim.cmd(math.max(height, minheight) .. "wincmd _")
end

--- Register the plugin's autocommands. Idempotent: the augroup is (re)created with `clear = true` on every
--- call, so a repeated `setup()` REPLACES the autocmds instead of stacking duplicate DiagnosticChanged /
--- height handlers onto the same group.
---@return nil
M.init = function()
    local group = vim.api.nvim_create_augroup("Lvimqfloc", { clear = true })
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
    vim.api.nvim_create_autocmd("ExitPre", {
        callback = function()
            pcall(vim.api.nvim_del_autocmd, diag_id)
        end,
        group = group,
    })
    vim.api.nvim_create_autocmd("FileType", {
        pattern = "qf",
        callback = function()
            qf_height(config.min_height)
        end,
        group = group,
    })
end

return M
