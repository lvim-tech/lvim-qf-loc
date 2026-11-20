-- lua/lvim-qf-loc/qf/jump.lua
-- `]q` / `[q` (quickfix) and `]l` / `[l` (location list) — Neovim's own `:cnext` / `:cprev` with three fixes:
--   • the file opens in an EDITOR window, never in a float (with `switchbuf=useopen`, `:cnext` opened the file
--     inside the area browser's preview float, which shows the same file);
--   • the step starts from the entry under the cursor (an entry opened another way leaves the list's index
--     behind), and on a fresh list the first press goes to entry 1 instead of skipping it;
--   • at either end the list wraps around (`jump.wrap`), instead of `E553: No more items`.
-- An open browser follows: its selected row moves to the entry jumped to.
--
---@module "lvim-qf-loc.qf.jump"

local api = vim.api
local config = require("lvim-qf-loc.config")

local M = {}

--- Can `w` take the entry's file? A tiled window that is not a quickfix / location list and does not pin its
--- buffer (`winfixbuf`). `files_only` further asks for a window showing a real file (not a tree, a dashboard,
--- a terminal, help …).
---@param w integer
---@param files_only? boolean
---@return boolean
local function can_host(w, files_only)
    if not api.nvim_win_is_valid(w) or api.nvim_win_get_config(w).relative ~= "" then
        return false
    end
    if vim.wo[w].winfixbuf then
        return false
    end
    local bt = vim.bo[api.nvim_win_get_buf(w)].buftype
    if files_only then
        return bt == ""
    end
    return bt ~= "quickfix"
end

--- The window the entry opens in — from ANYWHERE ]q is pressed (a list, the browser, a tree, the dashboard, a
--- terminal, a float): the current window when it shows a file, else the previous one, else any window showing
--- a file, else any window that can take one.
---@return integer?
local function target_window()
    local cur = api.nvim_get_current_win()
    local prev = vim.fn.win_getid(vim.fn.winnr("#"))
    for _, files_only in ipairs({ true, false }) do
        if can_host(cur, files_only) then
            return cur
        end
        if prev ~= 0 and can_host(prev, files_only) then
            return prev
        end
        for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
            if can_host(w, files_only) then
                return w
            end
        end
    end
    return nil
end

--- The window whose location list a `]l` walks: the current window when it owns one (a location list window
--- stands for its file window), else the target window.
---@param target integer
---@return integer
local function loc_owner(target)
    local cur = api.nvim_get_current_win()
    local info = vim.fn.getwininfo(cur)[1]
    if info and info.loclist == 1 then
        local owner = vim.fn.getloclist(cur, { filewinid = 0 }).filewinid
        if owner and owner ~= 0 then
            return owner
        end
    end
    if can_host(cur) then
        return cur
    end
    return target
end

--- Step through a list.
---@param kind "qf"|"loc"
---@param dir 1|-1
function M.step(kind, dir)
    local target = target_window()
    if not target then
        vim.notify("No window to open the entry in", vim.log.levels.INFO)
        return
    end
    local owner = kind == "loc" and loc_owner(target) or nil
    local what = owner and vim.fn.getloclist(owner, { items = 0, idx = 0 }) or vim.fn.getqflist({ items = 0, idx = 0 })
    local items = what.items or {}
    local valid = {}
    for i, e in ipairs(items) do
        if e.valid == 1 then
            valid[#valid + 1] = i
        end
    end
    if #valid == 0 then
        vim.notify(kind == "loc" and "No location list" or "No quickfix list", vim.log.levels.INFO)
        return
    end
    local idx = what.idx or 1
    -- WHERE YOU ARE decides the step, not only the list's own index: an entry may have been opened some other
    -- way (the browser's <CR>, a click, a search) without moving the index — stepping from the index then
    -- jumped BACK into another file. An entry under the cursor (its file, its line) is the base; the index
    -- wins a tie (two entries on the line).
    local tbuf = api.nvim_win_get_buf(target)
    local tline = api.nvim_win_get_cursor(target)[1]
    local function at(i)
        local e = items[i]
        return e and e.valid == 1 and e.bufnr == tbuf and e.lnum == tline
    end
    local base
    if at(idx) then
        base = idx
    else
        for i = 1, #items do
            if at(i) then
                base = i
                break
            end
        end
    end
    local n
    if not base and idx == 1 and items[1] and items[1].valid == 1 then
        n = 1 -- a fresh list, and you are not on its first entry: go there first instead of skipping it
    else
        base = base or idx
        for k = 1, #items do
            local i = base + dir * k
            if i < 1 or i > #items then
                if not config.jump.wrap then
                    break
                end
                i = ((i - 1) % #items) + 1
            end
            if items[i] and items[i].valid == 1 then
                n = i
                break
            end
            if i == base then
                break
            end
        end
    end
    if not n then
        vim.notify("No more items", vim.log.levels.INFO)
        return
    end
    local stay = api.nvim_get_current_win() ~= target -- pressed in the list / the browser: keep the focus there
    -- `switchbuf=useopen` sends :cc to a window already showing the file — the browser's preview FLOAT shows
    -- it: hold `useopen` back while a float shows the file, so the entry opens in the editor window
    local in_float = false
    for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
        if api.nvim_win_get_config(w).relative ~= "" and api.nvim_win_get_buf(w) == items[n].bufnr then
            in_float = true
            break
        end
    end
    local function go()
        local saved = vim.o.switchbuf
        if in_float then
            vim.o.switchbuf = ""
        end
        local ok, err = pcall(vim.cmd, ("%s %d"):format(kind == "loc" and "ll" or "cc", n))
        vim.o.switchbuf = saved
        if not ok then
            vim.notify(tostring(err):gsub("^Vim:", ""), vim.log.levels.WARN)
        end
    end
    if kind == "loc" and owner ~= target then
        -- a location list belongs to its window: jump there
        target = owner
    end
    if stay then
        api.nvim_win_call(target, go)
    else
        go()
    end
    M.ensure_open(kind, owner, target, n)
end

--- Is the list shown — its native window in this tab, or the browser?
---@param kind "qf"|"loc"
---@return boolean
local function list_shown(kind)
    if config.view == "area" then
        return require("lvim-qf-loc.qf.browser").is_open()
    end
    for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
        local info = vim.fn.getwininfo(w)[1]
        if info and info.quickfix == 1 and (info.loclist == 1) == (kind == "loc") then
            return true
        end
    end
    return false
end

--- Show the list after a step when it is not shown yet — in the current view — and put the cursor IN it (the
--- native window, or the browser's list in normal mode, out of the query, so the next ]q / [q goes on from
--- there); the list's selection is entry `n`.
---@param kind "qf"|"loc"
---@param owner integer?  the window owning the location list
---@param target integer  the editor window the entry opened in
---@param n integer  the entry
function M.ensure_open(kind, owner, target, n)
    local browser = require("lvim-qf-loc.qf.browser")
    if list_shown(kind) then
        pcall(browser.sync, n)
        return
    end
    if config.view == "area" then
        browser.open(kind == "loc" and owner or nil)
        vim.schedule(function()
            pcall(browser.sync, n)
            pcall(browser.focus_list)
        end)
        return
    end
    -- :copen / :lopen from the editor window: the list window opens and takes the cursor (on entry n)
    pcall(api.nvim_set_current_win, (kind == "loc" and owner) or target)
    pcall(vim.cmd, kind == "loc" and "lopen" or "botright copen")
end

--- Map the step keys (config.jump.keys), replacing Neovim's own ]q / [q / ]l / [l.
function M.setup()
    if not config.jump.enabled then
        return
    end
    local k = config.jump.keys or {}
    for _, m in ipairs({
        { k.qf_next, "qf", 1, "next quickfix entry" },
        { k.qf_prev, "qf", -1, "previous quickfix entry" },
        { k.loc_next, "loc", 1, "next location list entry" },
        { k.loc_prev, "loc", -1, "previous location list entry" },
    }) do
        if m[1] and m[1] ~= "" then
            vim.keymap.set("n", m[1], function()
                for _ = 1, vim.v.count1 do
                    M.step(m[2], m[3])
                end
            end, { silent = true, desc = "lvim-qf-loc: " .. m[4] })
        end
    end
end

return M
