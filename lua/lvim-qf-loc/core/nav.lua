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

--- Make the list stack's CURRENT list a non-empty one: the current list when it has entries, else the first
--- (oldest) non-empty list of the history. false when every list is empty.
---@param loc boolean  the current window's location-list stack (else the quickfix stack)
---@return boolean
local function current_or_first(loc)
    local get = loc and function(what)
        return vim.fn.getloclist(0, what)
    end or vim.fn.getqflist
    if (get({ size = 0 }).size or 0) > 0 then
        return true
    end
    for nr = 1, get({ nr = "$" }).nr or 0 do
        if (get({ nr = nr, size = 0 }).size or 0) > 0 then
            local cur = get({ nr = 0 }).nr
            if nr ~= cur then
                -- step through the history to it (:colder / :cnewer by the distance)
                local cmd = (nr < cur) and (loc and "lolder" or "colder") or (loc and "lnewer" or "cnewer")
                safe_fn(("%d%s"):format(math.abs(cur - nr), cmd))
            end
            return true
        end
    end
    return false
end

--- Open the quickfix window (`:copen`) on the current list — or, when that one is empty, on the first non-empty
--- list of the history; notify when there is none.
---@return nil
M.quick_fix_open = function()
    if not current_or_first(false) then
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

--- Open the current window's location-list window (`:lopen`) on its current list, or the first non-empty one of
--- its history; notify when there is none.
---@return nil
M.loc_list_open = function()
    if not current_or_first(true) then
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
