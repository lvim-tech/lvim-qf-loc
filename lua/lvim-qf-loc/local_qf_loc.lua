local utils = require("lvim-qf-loc.utils")

local M = {}

local function save_lists(kind, filename)
    local len = utils.length(kind)
    if len < 1 then
        utils.notify("There are no " .. kind .. " lists")
        return
    end

    local choices = { "Show current path", "Save", "Cancel" }
    vim.ui.select(choices, { prompt = "Save " .. kind .. " lists" }, function(choice)
        if not choice or choice == "Cancel" then
            return
        end

        if choice == "Show current path" then
            utils.notify(vim.fn.getcwd())
        elseif choice == "Save" then
            local data = {}
            for i = 1, len do
                local entry = utils.list_to_json(kind, i)
                table.insert(data, entry)
            end
            utils.write_file(vim.fn.getcwd() .. "/" .. filename, data)
            utils.notify("Saved " .. kind .. " lists to " .. filename)
        end
    end)
end

local function load_lists(kind, filename, setfn)
    local data = utils.read_file(vim.fn.getcwd() .. "/" .. filename)
    if not data then
        utils.notify("There are no saved " .. kind .. " lists")
        return
    end

    local len = utils.table_length(data)
    for i = 1, len do
        setfn(0, {}, " ", data[i])
    end
    utils.notify("Loaded " .. tostring(len) .. " " .. kind .. " list(s)")
end

M.quick_fix_menu_save = function()
    save_lists("quick_fix", ".lvim_qf.json")
end

M.quick_fix_menu_load = function()
    load_lists("quick_fix", ".lvim_qf.json", vim.fn.setqflist)
end

M.loc_list_menu_save = function()
    save_lists("loc", ".lvim_loc.json")
end

M.loc_list_menu_load = function()
    load_lists("loc", ".lvim_loc.json", vim.fn.setloclist)
end

return M
