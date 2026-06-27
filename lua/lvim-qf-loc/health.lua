-- lua/lvim-qf-loc/health.lua
-- `:checkhealth lvim-qf-loc` — verifies the runtime the qf module needs and warns about the two things that
-- actually break it: a too-old Neovim, and ANOTHER plugin (nvim-bqf / quicker.nvim) owning `quickfixtextfunc`
-- or the quickfix window at the same time. Reports the effective `view` and whether its dependencies are met.
--
---@module "lvim-qf-loc.health"

local config = require("lvim-qf-loc.config")

local M = {}

local health = vim.health
local start = health.start or health.report_start
local ok = health.ok or health.report_ok
local warn = health.warn or health.report_warn
local info = health.info or health.report_info

--- Run the health checks.
function M.check()
    start("lvim-qf-loc")

    -- Neovim version: the editable extmarks + inline virtual text the qf module relies on need 0.10+.
    if vim.fn.has("nvim-0.10") == 1 then
        ok("Neovim " .. tostring(vim.version()))
    else
        warn("Neovim 0.10+ is recommended (inline virtual text + extmark editing).")
    end

    -- lvim-utils: required by the area view + the browser (the popup, `:LvimQf browse` / `diagnostics`).
    local has_utils = pcall(require, "lvim-utils.picker")
    if has_utils then
        ok("lvim-utils found (area view / browser available).")
    else
        warn(
            "lvim-utils not found — the area view and `:LvimQf browse` are unavailable; the native view "
                .. "(editable + preview) still works."
        )
    end

    -- the effective view + its dependency
    info("view = " .. tostring(config.view) .. "  (preview " .. (config.preview.enabled and "on" or "off") .. ")")
    if config.view == "area" and not has_utils then
        warn("view = 'area' needs lvim-utils; falling back to the native window.")
    end

    -- ownership of quickfixtextfunc — the real conflict source. We claim it; a foreign value means another
    -- quickfix plugin (e.g. nvim-bqf / quicker.nvim) is fighting for the same window.
    if not config.edit.enabled then
        info("edit.enabled = false — the native quickfix is left read-only.")
    elseif vim.o.quickfixtextfunc == "v:lua.LvimQfLocTextFunc" then
        ok("quickfixtextfunc owned by lvim-qf-loc.")
    elseif vim.o.quickfixtextfunc == "" then
        info("quickfixtextfunc unset (lvim-qf-loc sets it on setup()).")
    else
        warn(
            "quickfixtextfunc is set by something else ("
                .. vim.o.quickfixtextfunc
                .. ") — disable nvim-bqf "
                .. "/ quicker.nvim so lvim-qf-loc can own the quickfix."
        )
    end

    -- flag the plugins this module replaces if they are still loaded
    for _, mod in ipairs({ "bqf", "quicker" }) do
        if package.loaded[mod] then
            warn("'" .. mod .. "' is loaded — this module replaces it; disable it to avoid two qf UIs.")
        end
    end
end

return M
