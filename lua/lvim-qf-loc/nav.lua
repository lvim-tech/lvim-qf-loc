local utils = require("lvim-qf-loc.utils")
local config = require("lvim-qf-loc.config")

local M = {}

M.quick_fix_next = function()
    local len = utils.length("quick_fix")
    local cur = utils.current("quick_fix")
    if cur >= len then
        if config.notify and len >= 1 then
            vim.cmd("silent copen")
            vim.notify("This is the last quickfix list", vim.log.levels.ERROR, {
                title = "LVIM LIST",
            })
        else
            if config.notify then
                vim.notify("There are no quickfix lists", vim.log.levels.ERROR, {
                    title = "LVIM LIST",
                })
            end
        end
    else
        vim.cmd("silent cnewer")
        vim.cmd("silent copen")
    end
end

M.quick_fix_prev = function()
    local len = utils.length("quick_fix")
    local cur = utils.current("quick_fix")
    if cur <= 1 then
        if config.notify and len >= 1 then
            vim.cmd("silent copen")
            vim.notify("This is the first quickfix list", vim.log.levels.ERROR, {
                title = "LVIM LIST",
            })
        else
            if config.notify then
                vim.notify("There are no quickfix lists", vim.log.levels.ERROR, {
                    title = "LVIM LIST",
                })
            end
        end
    else
        vim.cmd("silent colder")
        vim.cmd("silent copen")
    end
end

M.lock_next = function()
    local len = utils.length("loc")
    local cur = utils.current("loc")
    if cur >= len then
        if config.notify and len >= 1 then
            vim.cmd("silent lopen")
            vim.notify("This is the last loc list", vim.log.levels.ERROR, {
                title = "LVIM LIST",
            })
        else
            if config.notify then
                vim.notify("There are no loc lists", vim.log.levels.ERROR, {
                    title = "LVIM LIST",
                })
            end
        end
    else
        vim.cmd("silent lnewer")
        vim.cmd("silent lopen")
    end
end

M.lock_prev = function()
    local len = utils.length("loc")
    local cur = utils.current("loc")
    if cur <= 1 then
        if config.notify and len >= 1 then
            vim.cmd("silent lopen")
            vim.notify("This is the first loc list", vim.log.levels.ERROR, {
                title = "LVIM LIST",
            })
        else
            if config.notify then
                vim.notify("There are no loc lists", vim.log.levels.ERROR, {
                    title = "LVIM LIST",
                })
            end
        end
    else
        vim.cmd("silent lolder")
        vim.cmd("silent lopen")
    end
end

return M
