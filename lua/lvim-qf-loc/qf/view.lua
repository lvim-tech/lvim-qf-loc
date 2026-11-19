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
--- Put the cursor in the (location / quickfix) list window of this tab.
---@param loclist boolean
local function focus_list(loclist)
    for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
        local info = vim.fn.getwininfo(w)[1]
        if info and info.quickfix == 1 and (info.loclist == 1) == loclist then
            pcall(api.nvim_set_current_win, w)
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
    if close then
        close()
    elseif to == "native" then
        require("lvim-qf-loc.qf.browser").close() -- switched by command while the browser shows
    end
    vim.schedule(function()
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
            open_native(loclist_win)
        end
    end)
end

return M
