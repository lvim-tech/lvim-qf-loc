-- lua/lvim-qf-loc/qf/replace.lua
-- PROJECT-WIDE search & replace across a quickfix / location list — apply one substitution to the source line
-- of every entry at once (the far.vim / quickfix-reflector idea), built on the editable engine's crash-safe
-- writer (qf/edit.apply_changes): a line is only written when the file still matches what the entry pointed
-- at, so an externally-changed file is skipped, never clobbered. The pattern is a normal Vim regex (via
-- `substitute()`), so `\<word\>`, capture groups `\1`, case flags etc. all work.
--
---@module "lvim-qf-loc.qf.replace"

local api = vim.api
local edit = require("lvim-qf-loc.qf.edit")
local filecache = require("lvim-qf-loc.qf.filecache")
local notify = require("lvim-qf-loc.utils.notify")

local M = {}

--- Apply `pattern → replacement` (a Vim regex, global per line) to every valid entry's source line.
---@param loclist_win integer?  nil → the quickfix list; a window → that window's location list
---@param pattern string
---@param replacement string
function M.replace(loclist_win, pattern, replacement)
    if not pattern or pattern == "" then
        return
    end
    local items = loclist_win and vim.fn.getloclist(loclist_win, { items = 0 }).items
        or vim.fn.getqflist({ items = 0 }).items
    local cache = filecache.new()
    local changes, n = {}, 0
    for _, e in ipairs(items or {}) do
        if e.valid == 1 and e.bufnr and e.bufnr > 0 and api.nvim_buf_is_valid(e.bufnr) and e.lnum and e.lnum > 0 then
            local path = api.nvim_buf_get_name(e.bufnr)
            local orig = path ~= "" and cache:line(e.bufnr, path, e.lnum) or nil
            if orig then
                local ok, new = pcall(vim.fn.substitute, orig, pattern, replacement, "g")
                if ok and type(new) == "string" and new ~= orig then
                    changes[path] = changes[path] or {}
                    if changes[path][e.lnum] == nil then -- one write per line even if several entries share it
                        changes[path][e.lnum] = { new = new, orig = orig }
                        n = n + 1
                    end
                end
            end
        end
    end
    if n == 0 then
        notify("No matches to replace.", vim.log.levels.INFO)
        return
    end
    local applied, skipped = edit.apply_changes(changes)
    edit.rerender(loclist_win)
    notify(
        ("Replaced %d line(s)%s."):format(applied, skipped > 0 and (", skipped " .. skipped) or ""),
        vim.log.levels.INFO
    )
end

--- Prompt for the pattern + replacement, then run. `loclist_win` as in `replace`.
---@param loclist_win integer?
function M.prompt(loclist_win)
    vim.ui.input({ prompt = "Search (Vim regex): " }, function(pattern)
        if not pattern or pattern == "" then
            return
        end
        vim.ui.input({ prompt = "Replace with: " }, function(replacement)
            if replacement == nil then
                return
            end
            M.replace(loclist_win, pattern, replacement)
        end)
    end)
end

return M
