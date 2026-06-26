-- lua/lvim-qf-loc/qf/context.lua
-- Expand / collapse SURROUNDING CONTEXT in the quickfix — quicker.nvim's context feature, rebuilt cleanly and
-- made PER-ENTRY: `zo` opens context around the entry UNDER THE CURSOR only (like a fold), `zc` closes it.
-- Each entry's open amount lives in the list's `context` under our key as a map `{ ["bufnr:lnum:col"] =
-- {before, after} }` (col included, so two diagnostics on one line are distinct folds), so entries expand
-- independently. Context rows are `valid = 0` (so `:cnext` skips them), carry their owner entry (so `zo` on a
-- context row grows from the entry's line), and are sourced from the live buffer — they read/edit like real lines.
--
---@module "lvim-qf-loc.qf.context"

local api = vim.api
local config = require("lvim-qf-loc.config")

local M = {}

local KEY = "lvim_qf_loc_context" -- our slot inside the list's `context`

--- get/set accessors for the quickfix list OR a window's location list, so one code path serves both.
---@param loclist_win integer?
---@return fun(what: table): table get, fun(items: table[], ctx: table) set
local function accessors(loclist_win)
    if loclist_win then
        return function(what)
            return vim.fn.getloclist(loclist_win, what)
        end, function(items, ctx)
            vim.fn.setloclist(loclist_win, {}, "r", { items = items, context = ctx })
        end
    end
    return function(what)
        return vim.fn.getqflist(what)
    end, function(items, ctx)
        vim.fn.setqflist({}, "r", { items = items, context = ctx })
    end
end

--- The per-entry expansion map `{ ["bufnr:lnum"] = {before, after} }` from a list's context (empty = nothing
--- expanded). A copy, so callers mutate freely before writing it back.
---@param ctx any
---@return table<string, { before: integer, after: integer }>
local function state_map(ctx)
    local src = (type(ctx) == "table" and type(ctx[KEY]) == "table") and ctx[KEY] or {}
    local out = {}
    for k, v in pairs(src) do
        if type(v) == "table" then
            out[k] = { before = v.before or 0, after = v.after or 0 }
        end
    end
    return out
end

--- The stable per-entry key. INCLUDES col, so two diagnostics on the SAME line are DIFFERENT entries —
--- expanding one opens only that one; the other stays a plain entry, untouched.
---@param e table
---@return string
local function entry_key(e)
    return (e.bufnr or 0) .. ":" .. (e.lnum or 0) .. ":" .. (e.col or 0)
end

--- Whether ANY entry currently shows context (so a caller can branch).
---@param loclist_win integer?
---@return boolean
function M.is_expanded(loclist_win)
    local get = accessors(loclist_win)
    for _, st in pairs(state_map(get({ context = 0 }).context)) do
        if (st.before or 0) > 0 or (st.after or 0) > 0 then
            return true
        end
    end
    return false
end

--- The real (valid) entries of the list, in order.
---@param items table[]
---@return table[]
local function valid_entries(items)
    local out = {}
    for _, e in ipairs(items) do
        if e.valid == 1 and e.bufnr and e.bufnr > 0 then
            out[#out + 1] = e
        end
    end
    return out
end

--- The entry the user is acting on. On an entry row → that entry. On a CONTEXT row → the entry that OWNS that
--- context (recorded in the row's `user_data` when it was opened), so `zo` again grows from the ORIGINAL entry
--- line, not the cursor's context line. Falls back to the nearest real entry if no owner is recorded.
---@param items table[]
---@return table?
local function cursor_entry(items)
    local row = api.nvim_win_get_cursor(0)[1]
    local it = items[row]
    if it and it.valid == 1 then
        return it
    end
    if it and type(it.user_data) == "table" and it.user_data.lvim_owner then
        for _, e in ipairs(items) do
            if e.valid == 1 and entry_key(e) == it.user_data.lvim_owner then
                return e
            end
        end
    end
    for d = 1, #items do
        local up, dn = items[row - d], items[row + d]
        if up and up.valid == 1 and up.bufnr and up.bufnr > 0 then
            return up
        end
        if dn and dn.valid == 1 and dn.bufnr and dn.bufnr > 0 then
            return dn
        end
    end
    return nil
end

--- Rebuild the list from the per-entry `map`. Dead simple: every entry keeps its place and order, and an
--- EXPANDED entry just gets its `before` lines inserted ABOVE it + `after` lines BELOW it as context rows —
--- ALWAYS that many, with NO regard for the other entries. If such a context line coincides with another entry
--- elsewhere, that entry stays where it is and the line is simply shown twice (context here, entry there). The
--- cursor lands back on `anchor`.
---@param get fun(what: table): table
---@param set fun(items: table[], ctx: table)
---@param map table<string, { before: integer, after: integer }>
---@param anchor table?
local function rebuild(get, set, map, anchor)
    local cur = get({ items = 0, context = 0 })
    local ctx = type(cur.context) == "table" and cur.context or {}
    local new = {}
    for _, e in ipairs(valid_entries(cur.items)) do
        local key = entry_key(e)
        local st = map[key] or {}
        local before, after = st.before or 0, st.after or 0
        local ln = e.lnum or 0
        if
            (before > 0 or after > 0)
            and ln > 0
            and pcall(vim.fn.bufload, e.bufnr)
            and api.nvim_buf_is_loaded(e.bufnr)
        then
            local total = api.nvim_buf_line_count(e.bufnr)
            local lo = math.max(1, ln - before)
            -- context rows carry their OWNER (`lvim_owner`), so `zo`/`zc` while the cursor is on one grows/shrinks
            -- from this entry's original line, not the cursor line; they are DIMMED (apply_source_highlights)
            if lo <= ln - 1 then -- the `before` source lines
                for off, line in ipairs(api.nvim_buf_get_lines(e.bufnr, lo - 1, ln - 1, false)) do
                    new[#new + 1] = {
                        bufnr = e.bufnr,
                        lnum = lo + off - 1,
                        col = 1,
                        text = line,
                        valid = 0,
                        user_data = { lvim_owner = key },
                    }
                end
            end
            new[#new + 1] = e -- the entry itself, in place
            local hi = math.min(total, ln + after)
            if ln + 1 <= hi then -- the `after` source lines
                for off, line in ipairs(api.nvim_buf_get_lines(e.bufnr, ln, hi, false)) do
                    new[#new + 1] = {
                        bufnr = e.bufnr,
                        lnum = ln + off,
                        col = 1,
                        text = line,
                        valid = 0,
                        user_data = { lvim_owner = key },
                    }
                end
            end
        else
            new[#new + 1] = e -- unexpanded → just the entry
        end
    end
    ctx[KEY] = map
    local view = vim.fn.winsaveview()
    set(new, ctx)
    pcall(vim.fn.winrestview, view) -- keep scroll/column; the line is corrected next
    if anchor then
        for i, e in ipairs(new) do
            if e.bufnr == anchor.bufnr and e.lnum == anchor.lnum then
                pcall(api.nvim_win_set_cursor, 0, { i, 0 })
                break
            end
        end
    end
end

--- Expand context around the entry UNDER THE CURSOR (only that one) by `before`/`after` more lines.
--- Accumulates — pressing again on the same entry opens it further.
---@param loclist_win integer?
---@param opts? { before?: integer, after?: integer }
function M.expand(loclist_win, opts)
    opts = opts or {}
    local get, set = accessors(loclist_win)
    local cur = get({ items = 0, context = 0 })
    local ctx = type(cur.context) == "table" and cur.context or {}
    local e = cursor_entry(cur.items)
    if not (e and (e.lnum or 0) > 0) then -- nothing to expand around (no entry, or a position-less file row)
        return
    end
    local key = entry_key(e)
    local st = state_map(ctx)[key] or { before = 0, after = 0 } -- this entry's own current amount (keep growing it)
    st.before = st.before + (opts.before or config.context.before)
    st.after = st.after + (opts.after or config.context.after)
    -- ONE context open at a time: opening (or growing) this entry closes every other entry's context
    rebuild(get, set, { [key] = st }, e)
end

--- Collapse the context of the entry under the cursor (back to just that entry).
---@param loclist_win integer?
function M.collapse(loclist_win)
    local get, set = accessors(loclist_win)
    local cur = get({ items = 0, context = 0 })
    local ctx = type(cur.context) == "table" and cur.context or {}
    local e = cursor_entry(cur.items)
    if not e then
        return
    end
    local map = state_map(ctx)
    map[entry_key(e)] = nil -- close this entry's fold
    rebuild(get, set, map, e)
end

--- Toggle the context of the entry under the cursor.
---@param loclist_win integer?
function M.toggle(loclist_win)
    local get = accessors(loclist_win)
    local cur = get({ items = 0, context = 0 })
    local ctx = type(cur.context) == "table" and cur.context or {}
    local e = cursor_entry(cur.items)
    if not e then
        return
    end
    local st = state_map(ctx)[entry_key(e)]
    if st and ((st.before or 0) > 0 or (st.after or 0) > 0) then
        M.collapse(loclist_win)
    else
        M.expand(loclist_win)
    end
end

--- Map the expand/collapse keys in a quickfix/location buffer (called from the FileType qf hook). A
--- non-`z` context key is mapped directly; the `z` PREFIX is gated — only the configured `z`-context keys act
--- (zo/zc by default), and EVERY other `z<x>` (folds, `zz`, scrolls, …) is swallowed, so `z` is reserved for
--- context in the quickfix.
---@param qbuf integer
---@param loclist_win integer?
function M.setup_keys(qbuf, loclist_win)
    local k = config.context.keys
    local function is_z(key)
        return type(key) == "string" and #key == 2 and key:sub(1, 1) == "z"
    end
    local function map(lhs, fn)
        if lhs and lhs ~= "" and not is_z(lhs) then -- z-prefixed keys go through the gate below, not direct
            vim.keymap.set("n", lhs, fn, { buffer = qbuf, nowait = true, silent = true })
        end
    end
    map(k.expand, function()
        M.expand(loclist_win)
    end)
    map(k.collapse, function()
        M.collapse(loclist_win)
    end)
    map(k.toggle, function()
        M.toggle(loclist_win)
    end)
    -- The `z` gate: read the second key ourselves and act ONLY on the context z-keys; anything else is blocked.
    vim.keymap.set("n", "z", function()
        local ok, ch = pcall(vim.fn.getcharstr)
        if not ok or ch == nil or ch == "" then
            return
        end
        local combo = "z" .. ch
        if combo == k.expand then
            M.expand(loclist_win)
        elseif combo == k.collapse then
            M.collapse(loclist_win)
        elseif k.toggle and k.toggle ~= "" and combo == k.toggle then
            M.toggle(loclist_win)
        end
        -- any other `z<x>` (zf/za/zR/zz/zt/zb/…) is intentionally swallowed in the quickfix
    end, { buffer = qbuf, nowait = true, silent = true })
end

return M
