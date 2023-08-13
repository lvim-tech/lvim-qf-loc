local utils = require("lvim-qf-loc.utils")
local config = require("lvim-qf-loc.config")
local notify = require("lvim-ui-config.notify")
local ui_config = require("lvim-ui-config.config")
local select = require("lvim-ui-config.select")

local M = {}

M.quick_fix_menu_save = function()
    local len = utils.length("quick_fix")
    if config.notify and len < 1 then
        notify.error("There are no quickfix lists", {
            title = "LVIM LIST",
        })
    else
        local opts = ui_config.select({
            "Show current path",
            "Save",
            "Cancel",
        }, { prompt = "Save quickfix lists" }, {})
        select(opts, function(choice)
            if choice == "Show current path" then
                notify.info(vim.inspect(vim.fn.getcwd()), {
                    title = "LVIM LIST",
                })
            elseif choice == "Save" then
                local qflists = {}
                for i = 1, len do
                    local qf = utils.list_to_json("quick_fix", i)
                    table.insert(qflists, qf)
                end
                utils.write_file(vim.fn.getcwd() .. "/.lvim_qf.json", qflists)
            end
        end)
    end
end

M.quick_fix_menu_load = function()
    local local_qflists = utils.read_file(vim.fn.getcwd() .. "/.lvim_qf.json")
    if local_qflists ~= nil then
        local len = utils.table_length(local_qflists)
        for i = 1, len do
            vim.fn.setqflist({}, " ", local_qflists[i])
        end
    else
        notify.error("There are no saved quickfix lists", {
            title = "LVIM LIST",
        })
    end
end

M.loc_menu_save = function()
    local len = utils.length("loc")
    if config.notify and len < 1 then
        notify.error("There are no loc lists", {
            title = "LVIM LIST",
        })
    else
        local opts = ui_config.select({
            "Show current path",
            "Save",
            "Cancel",
        }, { prompt = "Save loc lists" }, {})
        select(opts, function(choice)
            if choice == "Show current path" then
                notify.info(vim.inspect(vim.fn.getcwd()), {
                    title = "LVIM LIST",
                })
            elseif choice == "Save" then
                local loclists = {}
                for i = 1, len do
                    local loc = utils.list_to_json("loc", i)
                    table.insert(loclists, loc)
                end
                utils.write_file(vim.fn.getcwd() .. "/.lvim_loc.json", loclists)
            end
        end)
    end
end

M.loc_menu_load = function()
    local local_loclists = utils.read_file(vim.fn.getcwd() .. "/.lvim_loc.json")
    if local_loclists ~= nil then
        local len = utils.table_length(local_loclists)
        for i = 1, len do
            vim.fn.setloclist(0, {}, " ", local_loclists[i])
        end
    else
        notify.error("There are no saved loc lists", {
            title = "LVIM LIST",
        })
    end
end

return M
