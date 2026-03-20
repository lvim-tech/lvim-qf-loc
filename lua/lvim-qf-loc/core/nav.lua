local utils = require("lvim-qf-loc.utils")

local M = {}

local function safe_fn(cmd)
    pcall(function()
        vim.cmd("silent " .. cmd)
    end)
end

M.quick_fix_open = function()
    if vim.tbl_isempty(vim.fn.getqflist()) then
        utils.notify("No quickfix lists available")
    else
        safe_fn("copen")
    end
end

M.quick_fix_close = function()
    safe_fn("cclose")
end

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

M.loc_list_open = function()
    if vim.tbl_isempty(vim.fn.getloclist(0)) then
        utils.notify("No location lists available")
    else
        safe_fn("lopen")
    end
end

M.loc_list_close = function()
    safe_fn("lclose")
end

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
