local utils = require("lvim-qf-loc.utils")
local config = require("lvim-qf-loc.config")
local notify = require("lvim-ui-config.notify")
local select = require("lvim-ui-config.select")

local M = {}

M.quick_fix_menu_choice = function()
    local len = utils.length("quick_fix")
    if config.notify and len < 1 then
        notify.error("There are no quickfix lists", {
            title = "LVIM LIST",
        })
    else
        local values_preview = {}
        local values_choice = {}
        local current_nr = utils.current("quick_fix")
        for i = 1, len do
            local title = utils.title("quick_fix", i)
            if i == current_nr then
                title = title .. " (Current)"
            end
            table.insert(values_preview, title)
            values_choice[title] = i
        end
        select(values_preview, {
            prompt = "Choice quickfix list",
        }, function(choice)
            local diff = values_choice[choice] - current_nr
            if diff > 0 then
                for _ = 1, diff do
                    vim.cmd("silent cnewer")
                end
            elseif diff < 0 then
                for _ = 1, -diff do
                    vim.cmd("silent colder")
                end
            end
            vim.cmd("silent copen")
        end, "editor")
    end
end

M.loc_menu_choice = function()
    local len = utils.length("loc")
    if config.notify and len < 1 then
        notify.error("There are no loc lists", {
            title = "LVIM LIST",
        })
    else
        local values_preview = {}
        local values_choice = {}
        local current_nr = utils.current("loc")
        for i = 1, len do
            local title = utils.title("loc", i)
            if i == current_nr then
                title = title .. " (Current)"
            end
            table.insert(values_preview, title)
            values_choice[title] = i
        end
        select(values_preview, {
            prompt = "Choice loc list",
        }, function(choice)
            local diff = values_choice[choice] - current_nr
            if diff > 0 then
                for _ = 1, diff do
                    vim.cmd("silent lnewer")
                end
            elseif diff < 0 then
                for _ = 1, -diff do
                    vim.cmd("silent lolder")
                end
            end
            vim.cmd("silent lopen")
        end, "editor")
    end
end

M.quick_fix_menu_delete = function()
    local len = utils.length("quick_fix")
    if config.notify and len < 1 then
        notify.error("There are no quickfix lists", {
            title = "LVIM LIST",
        })
    else
        local values_preview = {}
        local values_choice = {}
        local current_nr = utils.current("quick_fix")
        for i = 1, len do
            local title = utils.title("quick_fix", i)
            if i == current_nr then
                title = title .. " (Current)"
            end
            table.insert(values_preview, title)
            values_choice[title] = i
        end
        select(values_preview, {
            prompt = "Delete quickfix list",
        }, function(choice)
            if values_choice[choice] == current_nr then
                vim.cmd("silent cclose")
            end
            local updated_qflists = {}
            for i = 1, len do
                if i ~= values_choice[choice] then
                    local qf = utils.list_to_json("quick_fix", i)
                    table.insert(updated_qflists, qf)
                end
            end
            local update_len = utils.table_length(updated_qflists)
            vim.fn.setqflist({}, "f")
            for i = 1, update_len do
                vim.fn.setqflist({}, " ", updated_qflists[i])
            end
        end, "editor")
    end
end

M.loc_menu_delete = function()
    local len = utils.length("loc")
    if config.notify and len < 1 then
        notify.error("There are no loc lists", {
            title = "LVIM LIST",
        })
    else
        local values_preview = {}
        local values_choice = {}
        local current_nr = utils.current("loc")
        for i = 1, len do
            local title = utils.title("loc", i)
            if i == current_nr then
                title = title .. " (Current)"
            end
            table.insert(values_preview, title)
            values_choice[title] = i
        end
        select(values_preview, {
            prompt = "Delete loc list",
        }, function(choice)
            if values_choice[choice] == current_nr then
                vim.cmd("silent lclose")
            end
            local updated_loclists = {}
            for i = 1, len do
                if i ~= values_choice[choice] then
                    local loc = utils.list_to_json("loc", i)
                    table.insert(updated_loclists, loc)
                end
            end
            local update_len = utils.table_length(updated_loclists)
            vim.fn.setloclist(0, {}, "f")
            for i = 1, update_len do
                vim.fn.setloclist(0, {}, " ", updated_loclists[i])
            end
        end, "editor")
    end
end

return M
