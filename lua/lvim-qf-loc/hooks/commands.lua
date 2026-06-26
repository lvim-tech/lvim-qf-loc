local popup = require("lvim-qf-loc.ui.popup")
local browser = require("lvim-qf-loc.qf.browser")
local replace = require("lvim-qf-loc.qf.replace")
local history = require("lvim-qf-loc.qf.history")

local M = {}

-- Maps subcommand name → the tab label it should open on.
local qf_tabs = {
    navigate = "Navigate",
    switch = "Switch",
    delete = "Delete",
    storage = "Storage",
    diagnostics = "Diagnostics",
}

local loc_tabs = {
    navigate = "Navigate",
    switch = "Switch",
    delete = "Delete",
    storage = "Storage",
}

local function register(name, tab_map, open_fn)
    local keys = vim.tbl_keys(tab_map)
    table.sort(keys)

    vim.api.nvim_create_user_command(name, function(opts)
        local sub = opts.args ~= "" and opts.args or nil
        if sub and not tab_map[sub] then
            vim.notify(name .. ": unknown subcommand '" .. sub .. "'", vim.log.levels.WARN, { title = "LVIM LIST" })
            return
        end
        open_fn(sub and tab_map[sub] or nil)
    end, {
        nargs = "?",
        complete = function()
            return keys
        end,
    })
end

M.setup = function()
    register("LvimQf", qf_tabs, popup.open_qf)
    register("LvimLoc", loc_tabs, popup.open_loc)
    -- the browser: the entry list + a live real-Neovim preview in the lvim-utils area (preview / fuzzy / mark).
    vim.api.nvim_create_user_command("LvimQfBrowse", function()
        browser.open(nil)
    end, { desc = "Browse the quickfix list (live preview, fuzzy, mark, filter)" })
    vim.api.nvim_create_user_command("LvimLocBrowse", function()
        browser.open(vim.api.nvim_get_current_win())
    end, { desc = "Browse the current window's location list" })
    -- project-wide search & replace across the list's entries (prompts for the Vim regex + replacement)
    vim.api.nvim_create_user_command("LvimQfReplace", function()
        replace.prompt(nil)
    end, { desc = "Search & replace across the quickfix list" })
    vim.api.nvim_create_user_command("LvimLocReplace", function()
        replace.prompt(vim.api.nvim_get_current_win())
    end, { desc = "Search & replace across the location list" })
    -- a picker over the qf / loc history (jump to a past list)
    vim.api.nvim_create_user_command("LvimQfHistory", function()
        history.open(nil)
    end, { desc = "Pick from the quickfix history" })
    vim.api.nvim_create_user_command("LvimLocHistory", function()
        history.open(vim.api.nvim_get_current_win())
    end, { desc = "Pick from the location-list history" })
end

return M
