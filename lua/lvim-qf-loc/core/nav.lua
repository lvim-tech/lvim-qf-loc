-- lua/lvim-qf-loc/core/nav.lua
-- Direct list NAVIGATION for the `:LvimQf`/`:LvimLoc open|close|next|prev` subcommands. Thin, guarded wrappers
-- over the native `:copen`/`:cclose`/`:cnewer`/`:colder` (and the location twins): before opening they check the
-- list is non-empty, and next/prev clamp at the ends of the history stack (notifying instead of erroring). Every
-- `:cmd` is run silently through a pcall so a transient failure never bubbles up to the user.
--
---@module "lvim-qf-loc.core.nav"

local utils = require("lvim-qf-loc.utils")

local M = {}

--- Run an Ex command silently, swallowing any error.
---@param cmd string  the Ex command (without a leading `:`)
---@return nil
local function safe_fn(cmd)
    pcall(function()
        vim.cmd("silent " .. cmd)
    end)
end

--- Open the current quickfix window (`:copen`), or notify when there is no quickfix list.
---@return nil
M.quick_fix_open = function()
    if vim.tbl_isempty(vim.fn.getqflist()) then
        utils.notify("No quickfix lists available")
    else
        safe_fn("copen")
    end
end

--- Close the quickfix window (`:cclose`).
---@return nil
M.quick_fix_close = function()
    safe_fn("cclose")
end

--- Switch to the NEWER quickfix list in the history (`:cnewer`) and open it; clamp + notify at the newest.
---@return nil
M.quick_fix_next = function()
    local len = utils.length("quick_fix")
    local cur = utils.current("quick_fix")

    if len == 0 then
        utils.notify("No quickfix lists available")
        return
    end

    if cur >= len then
        utils.notify("Already at the last quickfix list")
        safe_fn("copen")
        return
    end

    vim.cmd("silent cnewer")
    safe_fn("copen")
end

--- Switch to the OLDER quickfix list in the history (`:colder`) and open it; clamp + notify at the oldest.
---@return nil
M.quick_fix_prev = function()
    local len = utils.length("quick_fix")
    local cur = utils.current("quick_fix")

    if len == 0 then
        utils.notify("No quickfix lists available")
        return
    end

    if cur <= 1 then
        utils.notify("Already at the first quickfix list")
        safe_fn("copen")
        return
    end

    vim.cmd("silent colder")
    safe_fn("copen")
end

--- Open the current window's location-list window (`:lopen`), or notify when there is no location list.
---@return nil
M.loc_list_open = function()
    if vim.tbl_isempty(vim.fn.getloclist(0)) then
        utils.notify("No location lists available")
    else
        safe_fn("lopen")
    end
end

--- Close the location-list window (`:lclose`).
---@return nil
M.loc_list_close = function()
    safe_fn("lclose")
end

--- Switch to the NEWER location list in the history (`:lnewer`) and open it; clamp + notify at the newest.
---@return nil
M.loc_list_next = function()
    local len = utils.length("loc")
    local cur = utils.current("loc")

    if len == 0 then
        utils.notify("No location lists available")
        return
    end

    if cur >= len then
        utils.notify("Already at the last location list")
        safe_fn("lopen")
        return
    end

    vim.cmd("silent lnewer")
    safe_fn("lopen")
end

--- Switch to the OLDER location list in the history (`:lolder`) and open it; clamp + notify at the oldest.
---@return nil
M.loc_list_prev = function()
    local len = utils.length("loc")
    local cur = utils.current("loc")

    if len == 0 then
        utils.notify("No location lists available")
        return
    end

    if cur <= 1 then
        utils.notify("Already at the first location list")
        safe_fn("lopen")
        return
    end

    vim.cmd("silent lolder")
    safe_fn("lopen")
end

return M
