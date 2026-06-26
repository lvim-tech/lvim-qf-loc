-- lua/lvim-qf-loc/qf/filecache.lua
-- A tiny, robust source-line cache for the editable quickfix: given an entry's file + line, return the live
-- text of that line. Loaded buffers are read directly (always current); unloaded files are read from disk
-- ONCE and cached. Every read is guarded — a missing/unreadable file yields nil, never an error.
--
---@module "lvim-qf-loc.qf.filecache"

local api = vim.api
local M = {}

---@class LvimQfFileCache
---@field disk table<string, string[]>  path → its lines (read from disk, lazily)
local Cache = {}
Cache.__index = Cache

--- A fresh cache.
---@return LvimQfFileCache
function M.new()
    return setmetatable({ disk = {} }, Cache)
end

--- The text of line `lnum` (1-based) of the entry's file, or nil when it cannot be read. A loaded buffer wins
--- (it reflects unsaved edits); otherwise the file is read from disk once and cached.
---@param bufnr integer?  the entry's buffer handle (may be unloaded / invalid)
---@param path string  the entry's file path
---@param lnum integer
---@return string?
function Cache:line(bufnr, path, lnum)
    if lnum < 1 then
        return nil
    end
    if bufnr and bufnr > 0 and api.nvim_buf_is_loaded(bufnr) then
        local ok, lines = pcall(api.nvim_buf_get_lines, bufnr, lnum - 1, lnum, false)
        if ok and lines[1] ~= nil then
            return lines[1]
        end
        return nil
    end
    local disk = self.disk[path]
    if disk == nil then
        local ok, lines = pcall(vim.fn.readfile, path)
        disk = (ok and type(lines) == "table") and lines or {}
        self.disk[path] = disk
    end
    return disk[lnum]
end

return M
