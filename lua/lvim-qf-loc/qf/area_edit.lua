-- lua/lvim-qf-loc/qf/area_edit.lua
-- EDIT MODE for the area browser: the native window's in-place editing, brought to the browser's list. The
-- picker's list is a rendered view (its rows are redrawn on every move), so it is not edited itself: an editable
-- float is laid EXACTLY over the list window instead, holding the visible rows in the same order. As in the
-- native window, each row's buffer text is the entry's SOURCE LINE (a file list: its path) and the
-- `N │ file │ lnum, col │` columns are inline virtual text, so an edit can never break them; the entry behind each
-- row rides on an extmark. `:w` writes through the same crash-safe core as the native window
-- (`edit.apply_changes` / `edit.apply_renames`); `<Esc>` / `q` leave and the browser shows the new text. The
-- picker's selection follows the cursor, so its preview keeps showing the row being edited.
---@module "lvim-qf-loc.qf.area_edit"

local api = vim.api
local config = require("lvim-qf-loc.config")
local notify = require("lvim-qf-loc.utils.notify")

local M = {}

local NS = api.nvim_create_namespace("lvim-qf-loc-area-edit")

---@class LvimQfLocAreaEdit
---@field buf integer
---@field win integer
---@field list integer      the browser's list window the float covers
---@field handle table      the browser's picker handle
---@field loclist_win integer?
---@field kind "line"|"path"
---@field rows table<integer, table>  extmark id → { item, orig }
---@field group integer

---@type LvimQfLocAreaEdit?
local active

--- The editable text of a browser row: what follows its locator columns.
---@param it table
---@return string
local function body_of(it)
    return (it.text or ""):sub((it.locator_bytes or 0) + 1)
end

--- The row's columns as inline virtual-text chunks, coloured by the row's own spans (the browser's look).
---@param it table
---@return table[]
local function prefix_of(it)
    local text, lead = it.text or "", it.locator_bytes or 0
    local hl_at = {}
    for _, sp in ipairs(it.hl_spans or {}) do
        if sp[1] < lead then
            for b = sp[1], math.min(sp[2], lead) - 1 do
                hl_at[b] = sp[3]
            end
        end
    end
    local chunks, b = {}, 0
    while b < lead do
        local hl, e = hl_at[b], b
        while e < lead and hl_at[e] == hl do
            e = e + 1
        end
        chunks[#chunks + 1] = { text:sub(b + 1, e), hl or "Normal" }
        b = e
    end
    table.insert(chunks, 1, { " ", "Normal" }) -- the picker's lead (mark) column
    return chunks
end

--- Lay the rows: buffer text, the virtual columns + entry extmarks, and the source syntax colours.
---@param s LvimQfLocAreaEdit
---@param items table[]
local function lay(s, items)
    local lines = {}
    for i, it in ipairs(items) do
        lines[i] = body_of(it)
    end
    vim.bo[s.buf].modifiable = true
    api.nvim_buf_set_lines(s.buf, 0, -1, false, lines)
    api.nvim_buf_clear_namespace(s.buf, NS, 0, -1)
    s.rows = {}
    for i, it in ipairs(items) do
        local ok, id = pcall(api.nvim_buf_set_extmark, s.buf, NS, i - 1, 0, {
            virt_text = prefix_of(it),
            virt_text_pos = "inline",
            right_gravity = false,
        })
        if ok then
            s.rows[id] = { item = it, orig = lines[i] }
        end
        local lead = it.locator_bytes or 0
        for _, sp in ipairs(it.hl_spans or {}) do
            if sp[1] >= lead then
                pcall(api.nvim_buf_set_extmark, s.buf, NS, i - 1, sp[1] - lead, {
                    end_col = sp[2] - lead,
                    hl_group = sp[3],
                    priority = 90,
                })
            end
        end
        for _, m in ipairs(it.match_bytes or {}) do -- the grep match, marked as in the list
            pcall(api.nvim_buf_set_extmark, s.buf, NS, i - 1, m.c0 - lead, {
                end_col = m.c1 - lead,
                hl_group = "LvimQfLocMatch",
                priority = 200,
            })
        end
    end
    vim.bo[s.buf].modified = false
end

--- The browser item rendered on buffer row `row` (1-based), via its extmark.
---@param s LvimQfLocAreaEdit
---@param row integer
---@return table?
local function item_at(s, row)
    local m = api.nvim_buf_get_extmarks(s.buf, NS, { row - 1, 0 }, { row - 1, -1 }, {})
    for _, x in ipairs(m) do
        if s.rows[x[1]] then
            return s.rows[x[1]].item
        end
    end
end

--- Re-read the visible rows from the (just refreshed) browser and lay them again, keeping the cursor row.
---@param s LvimQfLocAreaEdit
---@param tries integer
local function relay(s, tries)
    if active ~= s or not api.nvim_buf_is_valid(s.buf) then
        return
    end
    local items = s.handle.visible()
    if #items == 0 and tries > 0 then
        vim.defer_fn(function()
            relay(s, tries - 1)
        end, 20)
        return
    end
    local cur = api.nvim_win_is_valid(s.win) and api.nvim_win_get_cursor(s.win) or { 1, 0 }
    lay(s, items)
    if api.nvim_win_is_valid(s.win) then
        pcall(api.nvim_win_set_cursor, s.win, { math.min(cur[1], math.max(1, #items)), cur[2] })
    end
end

--- Write the changed rows to their files (or rename the edited paths), then show the new text everywhere.
---@param s LvimQfLocAreaEdit
local function apply(s)
    local edit = require("lvim-qf-loc.qf.edit")
    local lines = api.nvim_buf_get_lines(s.buf, 0, -1, false)
    local applied, skipped, conflicts = 0, 0, {}
    if s.kind == "path" then
        local renames = {}
        for _, m in ipairs(api.nvim_buf_get_extmarks(s.buf, NS, 0, -1, {})) do
            local r, new = s.rows[m[1]], lines[m[2] + 1]
            if r and new then
                new = vim.trim(new)
                if new ~= "" and new ~= r.orig then
                    renames[#renames + 1] = {
                        old = r.item.path,
                        new = vim.fn.fnamemodify(new, ":p"),
                        bufnr = r.item.qf_entry and r.item.qf_entry.bufnr,
                    }
                end
            end
        end
        applied, skipped = edit.apply_renames(renames)
    else
        local changes, conflicted = {}, {}
        for _, m in ipairs(api.nvim_buf_get_extmarks(s.buf, NS, 0, -1, {})) do
            local r, new = s.rows[m[1]], lines[m[2] + 1]
            if r and new and new ~= r.orig then
                local path, lnum = r.item.path, r.item.lnum
                local key = path .. "\0" .. lnum
                changes[path] = changes[path] or {}
                local prev = changes[path][lnum]
                if conflicted[key] then
                    changes[path][lnum] = nil
                elseif prev and prev.new ~= new then
                    -- two rows of one source line disagree: report it and leave the line untouched
                    conflicts[#conflicts + 1] = ("%s:%d"):format(path, lnum)
                    conflicted[key] = true
                    changes[path][lnum] = nil
                else
                    changes[path][lnum] = { new = new, orig = r.orig }
                end
            end
        end
        applied, skipped = edit.apply_changes(changes)
    end
    vim.bo[s.buf].modified = false
    -- the list's own entries are re-read (a renamed buffer, the new source lines), then the browser and these rows
    pcall(edit.rerender, s.loclist_win)
    require("lvim-qf-loc.qf.browser").refresh(s.loclist_win)
    relay(s, 10)
    local verb = s.kind == "path" and "Renamed %d file(s)%s." or "Applied %d edit(s)%s."
    if #conflicts > 0 then
        notify(
            ("Applied %d, skipped %d; conflicts: %s"):format(applied, skipped, table.concat(conflicts, ", ")),
            vim.log.levels.WARN
        )
    elseif applied > 0 or skipped > 0 then
        notify(verb:format(applied, skipped > 0 and (", skipped " .. skipped) or ""), vim.log.levels.INFO)
    end
end

--- Place the float over the list window's rows.
---@param s LvimQfLocAreaEdit
local function place(s)
    if not (api.nvim_win_is_valid(s.win) and api.nvim_win_is_valid(s.list)) then
        return
    end
    local lc = api.nvim_win_get_config(s.list)
    pcall(api.nvim_win_set_config, s.win, {
        relative = "win",
        win = s.list,
        row = 0, -- relative to the list's text area: its winbar row stays visible above
        col = 0,
        width = api.nvim_win_get_width(s.list),
        height = math.max(1, api.nvim_win_get_height(s.list)),
        zindex = (lc.zindex or 50) + 5,
    })
end

--- Whether edit mode is open.
---@return boolean
function M.is_open()
    return active ~= nil and api.nvim_win_is_valid(active.win)
end

--- Leave edit mode: back to the browser's list, its selection on the row the cursor was on. With unsaved
--- edits, ask first (apply / discard / stay).
---@param force boolean?  leave without asking (the browser is gone)
function M.close(force)
    local s = active
    if not s then
        return
    end
    if not force and api.nvim_buf_is_valid(s.buf) and vim.bo[s.buf].modified then
        local c = vim.fn.confirm("Apply the edits?", "&Yes\n&No\n&Cancel", 3)
        if c == 1 then
            apply(s)
        elseif c ~= 2 then
            return
        end
    end
    local it = api.nvim_win_is_valid(s.win) and item_at(s, api.nvim_win_get_cursor(s.win)[1]) or nil
    active = nil
    pcall(api.nvim_del_augroup_by_id, s.group)
    if api.nvim_win_is_valid(s.win) then
        pcall(api.nvim_win_close, s.win, true)
    end
    if api.nvim_buf_is_valid(s.buf) then
        pcall(api.nvim_buf_delete, s.buf, { force = true })
    end
    if not force and s.handle.is_open() then
        s.handle.focus_list()
        if it and it.qf_idx then
            local idx = it.qf_idx
            s.handle.select(function(src)
                return type(src) == "table" and src.qf_idx == idx
            end)
        end
    end
end

--- Make the open browser's visible rows editable.
---@param handle table?        the browser's picker handle
---@param loclist_win integer?
function M.open(handle, loclist_win)
    if M.is_open() or not (handle and handle.is_open()) then
        return
    end
    local list = handle.list_win and handle.list_win()
    if not list then
        return
    end
    local items, sel = handle.visible()
    if #items == 0 then
        return
    end
    local kind = items[1].qf_edit
    if not kind then
        notify("This list has no editable text (descriptions only).", vim.log.levels.INFO)
        return
    end

    local buf = api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = "acwrite" -- `:w` runs our BufWriteCmd
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].swapfile = false
    pcall(api.nvim_buf_set_name, buf, "lvim-qf-loc://edit/" .. buf)
    local win = api.nvim_open_win(buf, true, {
        relative = "win",
        win = list,
        row = 0,
        col = 0,
        width = 1,
        height = 1,
        style = "minimal",
        focusable = true,
    })
    local s = {
        buf = buf,
        win = win,
        list = list,
        handle = handle,
        loclist_win = loclist_win,
        kind = kind,
        rows = {},
        group = api.nvim_create_augroup("LvimQfLocAreaEdit", { clear = true }),
    }
    active = s
    place(s)
    -- the list window's own look (its background, cursor line), no wrap: one entry, one row
    vim.wo[win].winhighlight = vim.wo[list].winhighlight
    vim.wo[win].wrap = false
    vim.wo[win].cursorline = true
    vim.w[win].lvim_frame = true -- part of the browser's frame: never dimmed with the editor behind it
    lay(s, items)
    local it = items[sel or 1] or items[1]
    local c0 = it.match_bytes and it.match_bytes[1] and (it.match_bytes[1].c0 - (it.locator_bytes or 0)) or 0
    pcall(api.nvim_win_set_cursor, win, { math.max(1, sel or 1), math.max(0, c0) })

    api.nvim_create_autocmd("BufWriteCmd", {
        group = s.group,
        buffer = buf,
        callback = function()
            -- acknowledge the write now, apply on the next tick (file edits are blocked by textlock in here)
            vim.bo[buf].modified = false
            vim.schedule(function()
                if active == s and api.nvim_buf_is_valid(buf) then
                    local ok, err = pcall(apply, s)
                    if not ok then
                        notify("Edit apply failed: " .. tostring(err), vim.log.levels.ERROR)
                    end
                end
            end)
        end,
    })
    -- the browser's selection (and so its preview) follows the row being edited
    api.nvim_create_autocmd("CursorMoved", {
        group = s.group,
        buffer = buf,
        callback = function()
            local cur = item_at(s, api.nvim_win_get_cursor(win)[1])
            if cur and cur.qf_idx and s.handle.is_open() then
                local idx = cur.qf_idx
                s.handle.select(function(src)
                    return type(src) == "table" and src.qf_idx == idx
                end)
                -- the select re-renders the list underneath: keep the cursor here
                if api.nvim_get_current_win() ~= win and api.nvim_win_is_valid(win) then
                    api.nvim_set_current_win(win)
                end
            end
        end,
    })
    api.nvim_create_autocmd("WinClosed", {
        group = s.group,
        callback = function(ev)
            local closed = tonumber(ev.match)
            if closed == list then
                vim.schedule(function()
                    M.close(true)
                end)
            elseif closed == win then
                vim.schedule(function()
                    if active == s then
                        M.close(true)
                        if s.handle.is_open() then
                            s.handle.focus_list()
                        end
                    end
                end)
            end
        end,
    })
    api.nvim_create_autocmd({ "WinResized", "VimResized" }, {
        group = s.group,
        callback = function()
            place(s)
        end,
    })
    for _, lhs in ipairs({ "<Esc>", "q" }) do
        vim.keymap.set("n", lhs, function()
            M.close()
        end, { buffer = buf, nowait = true, desc = "Leave edit mode" })
    end
    notify(":w writes the edits · <Esc> / q back to the list", vim.log.levels.INFO)
end

return M
