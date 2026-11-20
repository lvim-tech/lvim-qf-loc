-- lua/lvim-qf-loc/qf/view.lua
-- Switch the list between the two views (`config.view`): the NATIVE editable quickfix window and the AREA
-- browser — live, on the list being looked at. The choice sticks for the session, so a later `:copen` opens the
-- view switched to.
--
---@module "lvim-qf-loc.qf.view"

local api = vim.api
local config = require("lvim-qf-loc.config")

local M = {}

--- Open the list in the native quickfix window (the editable view).
---@param loclist_win integer?  the window owning a location list; nil = the quickfix list
--- Put the cursor in the (location / quickfix) list window of this tab, laid out at once (see
--- `edit.render_now`: it would otherwise paint raw for a frame).
---@param loclist boolean
local function focus_list(loclist)
    for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
        local info = vim.fn.getwininfo(w)[1]
        if info and info.quickfix == 1 and (info.loclist == 1) == loclist then
            pcall(api.nvim_set_current_win, w)
            pcall(require("lvim-qf-loc.qf.edit").render_now, w)
            return
        end
    end
end

local function open_native(loclist_win)
    if loclist_win and api.nvim_win_is_valid(loclist_win) then
        api.nvim_win_call(loclist_win, function()
            pcall(vim.cmd, "lopen")
        end)
        focus_list(true) -- the list, not the window it was opened from: you switched to work in it
        return
    end
    -- `:copen` from a floating window (the browser's prompt, a dock panel) fails: run it from a tiled one
    local from = api.nvim_get_current_win()
    if api.nvim_win_get_config(from).relative ~= "" then
        for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
            if api.nvim_win_get_config(w).relative == "" then
                from = w
                break
            end
        end
    end
    api.nvim_win_call(from, function()
        pcall(vim.cmd, "copen")
    end)
    focus_list(false)
end

--- Run a view swap (close one, open the other) as ONE screen change, the way the dock swaps two panels: the
--- backdrop is held across it (else the editor flashes bright between the two views) and the area zone reflows
--- once, not twice (release, then reserve).
---@param fn fun()
---@param zone? boolean  coalesce through the area zone's handoff (the browser is OPENED — a zone consumer);
---   leaving the zone (area → native) instead holds the screen itself and repaints once, fully, at the end: the
---   zone handoff's own flush painted the screen mid-way (cleared, before the windows were redrawn) — a blank
---   frame between the two views
local function smooth(fn, zone)
    local okd, dim = pcall(require, "lvim-utils.dim")
    local held = okd and type(dim.hold_backdrop) == "function"
    if held then
        dim.hold_backdrop(true)
    end
    local oks, surface = pcall(require, "lvim-ui.surface")
    local ok, err = pcall(function()
        if zone and oks and type(surface.zone_handoff) == "function" then
            surface.zone_handoff(fn)
        else
            local lz = vim.o.lazyredraw
            vim.o.lazyredraw = true
            local okf, errf = pcall(fn)
            vim.o.lazyredraw = lz
            pcall(api.nvim__redraw, { valid = false, flush = true })
            if not okf then
                error(errf)
            end
        end
    end)
    if held then
        dim.release_backdrop_when_settled()
    end
    if not ok then
        vim.notify("lvim-qf-loc: " .. tostring(err), vim.log.levels.WARN)
    end
end

--- Switch to the other view and show the same list there.
---@param loclist_win integer?  the window owning a location list; nil = the quickfix list
---@param close? fun()  closes the view being left (the browser passes its own close)
function M.switch(loclist_win, close)
    -- the location-list WINDOW itself closes below: hold on to the file window owning the list instead
    if loclist_win and api.nvim_win_is_valid(loclist_win) then
        local info = vim.fn.getwininfo(loclist_win)[1]
        if info and info.loclist == 1 then
            local owner = vim.fn.getloclist(loclist_win, { filewinid = 0 }).filewinid
            loclist_win = (owner and owner ~= 0) and owner or nil
        end
    end
    local to = config.view == "area" and "native" or "area"
    config.view = to
    smooth(function()
        if to == "area" then
            -- the native window goes, the browser takes the list
            if loclist_win and api.nvim_win_is_valid(loclist_win) then
                api.nvim_win_call(loclist_win, function()
                    pcall(vim.cmd, "lclose")
                end)
            else
                pcall(vim.cmd, "cclose")
            end
            require("lvim-qf-loc.qf.browser").open(loclist_win)
        else
            -- the native list FIRST, then the browser goes: closing the browser releases its zone rows and the
            -- zone repaints right then — with the list already there that repaint is the final picture, not a
            -- blank screen between the two views
            open_native(loclist_win)
            -- its preview float is placed for the layout WITH the browser's rows; they are about to go, so
            -- drop it now and lay it out once below, in its final place (else it jumped after a frame)
            pcall(require("lvim-qf-loc.qf.preview").close)
            if close then
                close()
            else
                require("lvim-qf-loc.qf.browser").close() -- switched by command while the browser shows
            end
            focus_list(loclist_win ~= nil) -- closing the browser hands the focus back to where it came from
        end
    end, to == "area")
end

--- Go to the NEWER (`dir` 1) / OLDER (-1) list of the history and show it in the view it is in: the native
--- window follows by itself; the browser is rebuilt on the new list. At either end: a notice, nothing else.
---@param kind "qf"|"loc"
---@param dir 1|-1
---@param loclist_win? integer  the window owning the location list (loc)
function M.cycle(kind, dir, loclist_win)
    local loc = kind == "loc"
    local owner = loclist_win
    if loc and not (owner and api.nvim_win_is_valid(owner)) then
        -- pressed in a location-list window: its file window owns the list
        local info = vim.fn.getwininfo(api.nvim_get_current_win())[1]
        owner = (info and info.loclist == 1) and vim.fn.getloclist(0, { filewinid = 0 }).filewinid
            or api.nvim_get_current_win()
    end
    local function get(what)
        return loc and vim.fn.getloclist(owner, what) or vim.fn.getqflist(what)
    end
    local len, cur = get({ nr = "$" }).nr or 0, get({ nr = 0 }).nr or 0
    local name = loc and "location" or "quickfix"
    if len == 0 then
        vim.notify(("No %s lists"):format(name), vim.log.levels.INFO)
        return
    end
    if (dir > 0 and cur >= len) or (dir < 0 and cur <= 1) then
        vim.notify(("Already at the %s %s list"):format(dir > 0 and "newest" or "oldest", name), vim.log.levels.INFO)
        return
    end
    local cmd = (dir > 0 and (loc and "lnewer" or "cnewer")) or (loc and "lolder" or "colder")
    local run = function()
        pcall(vim.cmd, "silent " .. cmd)
    end
    if loc then
        api.nvim_win_call(owner, run)
    else
        run()
    end
    if config.view == "area" then
        local browser = require("lvim-qf-loc.qf.browser")
        -- the open browser swaps its rows in place (no close / re-open → no flicker); else it opens
        if not browser.refresh(loc and owner or nil) then
            browser.open(loc and owner or nil)
        end
    end
end

return M
