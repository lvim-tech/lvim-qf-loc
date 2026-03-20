local popup = require("lvim-qf-loc.ui.popup")

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
end

return M
