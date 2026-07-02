-- lua/lvim-qf-loc/utils/init.lua
-- Shared helpers for the plugin: quickfix / location-list introspection (how many lists, which is current,
-- a list's title), a JSON-safe serialiser for persisting lists (`list_fix`/`list_to_json` — drop volatile
-- `bufnr`/`nr`, resolve paths), small file read/write/delete wrappers, and the notify shim. Pure utilities,
-- no side effects beyond the file ops.
--
---@module "lvim-qf-loc.utils"

local M = {}

--- Emit a plugin notification (respects `config.notify`); `require("lvim-qf-loc.utils").notify(msg, level)`.
M.notify = require("lvim-qf-loc.utils.notify")

--- Count the entries of a table (works for non-sequence tables, unlike `#`).
---@param tbl table
---@return integer
M.table_length = function(tbl)
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

--- The number of lists in the quickfix or location-list history stack.
---@param list "quick_fix"|"loc"
---@return integer?
M.length = function(list)
    if list == "quick_fix" then
        return vim.fn.getqflist({ nr = "$" })["nr"]
    elseif list == "loc" then
        return vim.fn.getloclist(0, { nr = "$" })["nr"]
    end
end

--- The 1-based index of the CURRENT list in the quickfix / location-list history stack.
---@param list "quick_fix"|"loc"
---@return integer?
M.current = function(list)
    if list == "quick_fix" then
        return vim.fn.getqflist({ nr = 0 })["nr"]
    elseif list == "loc" then
        return vim.fn.getloclist(0, { nr = 0 })["nr"]
    end
end

--- The title of list number `id` in the quickfix / location-list history stack.
---@param list "quick_fix"|"loc"
---@param id integer
---@return string?
M.title = function(list, id)
    if list == "quick_fix" then
        return vim.fn.getqflist({ nr = id, all = 1 })["title"]
    elseif list == "loc" then
        return vim.fn.getloclist(0, { nr = id, all = 1 })["title"]
    end
end

--- Make a list JSON-safe for persistence: resolve each item's filename from its (still-valid) buffer, then
--- drop the volatile `bufnr`/`nr` fields. Returns `{ title, items }`.
---@param list table  a `getqflist({ all = 1 })`-shaped table
---@return table
M.list_fix = function(list)
    for i, d in ipairs(list.items) do
        if vim.api.nvim_buf_is_valid(d.bufnr) then
            d.filename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(d.bufnr), ":p")
        end
        d.bufnr = nil
        d.nr = nil
        list.items[i] = d
    end
    local clear_list = {
        title = list.title,
        items = list.items,
    }
    return clear_list
end

--- The JSON-safe form of list number `id` (title + path-resolved items), ready for `write_file`.
---@param list "quick_fix"|"loc"
---@param id integer
---@return table
M.list_to_json = function(list, id)
    local list_content
    if list == "quick_fix" then
        list_content = vim.fn.getqflist({ nr = id, all = 1 })
    elseif list == "loc" then
        list_content = vim.fn.getloclist(0, { nr = id, all = 1 })
    end
    return M.list_fix(list_content)
end

--- Read and JSON-decode a file. Returns nil when the file is unreadable or not decodable.
---@param file string  absolute path
---@return table?
M.read_file = function(file)
    local content
    local file_content_ok, _ = pcall(function()
        content = vim.fn.readfile(file)
    end)
    if not file_content_ok then
        return nil
    end
    if type(content) == "table" then
        return vim.fn.json_decode(content)
    else
        return nil
    end
end

--- Write `content` to a file (a table is JSON-encoded first). Silently no-ops when the file can't be opened.
---@param file string  absolute path
---@param content string|table
---@return nil
M.write_file = function(file, content)
    local f = io.open(file, "w")
    if f ~= nil then
        if type(content) == "table" then
            content = vim.fn.json_encode(content)
        end
        f:write(content)
        f:close()
    end
end

--- Delete a saved-lists file. Returns true only if it existed AND was removed (so the caller can tell
--- "deleted" from "there was nothing to delete").
---@param file string  absolute path
---@return boolean
M.delete_file = function(file)
    if vim.fn.filereadable(file) == 0 then
        return false
    end
    return vim.fn.delete(file) == 0
end

return M
