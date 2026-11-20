-- lua/lvim-qf-loc/qf/browser.lua
-- The quickfix / location-list BROWSER — a live preview of the entry under the cursor, built on the
-- lvim-utils stack: the list + a REAL-Neovim preview open in OUR area (the surface chassis, same
-- zone as the pickers and the lsp navigation), NOT a native qf float, and with neither LuaJIT FFI
-- nor scroll math against the window's internals (the brittle, crash-prone parts of the usual
-- implementations, deliberately dropped). The list is the
-- lvim-picker list — so it comes with fuzzy narrowing, the Tab mark dot, `<C-q>` → a new list, and the
-- severity filter bar for free; this file just sources the rows from `getqflist`/`getloclist` and styles them.
--
---@module "lvim-qf-loc.qf.browser"

local config = require("lvim-qf-loc.config")
local notify = require("lvim-qf-loc.utils.notify")

local M = {}

--- The browser's identity in the dock stack (`opts.key` of the picker it opens through).
local KEY = "lvim-qf-loc"

local browser_keys -- (defined below, before M.open)

--- The grep a list came from (lvim-picker keeps `{ pattern, regex }` in the list's context), or {}.
---@param loclist_win integer?
---@return table
local function grep_of(loclist_win)
    local what = loclist_win and vim.fn.getloclist(loclist_win, { context = 0 }) or vim.fn.getqflist({ context = 0 })
    local c = type(what.context) == "table" and what.context.lvim_picker
    return type(c) == "table" and c or {}
end

---@type table?  the open browser's picker handle (`select`, `is_open`)
local open_handle
---@type integer?  the window whose location list the open browser shows (nil: the quickfix list)
local open_loclist

--- The raw list (quickfix or a window's location list) as browser items, drawn as the editable quickfix draws
--- its rows (qf/edit.lua): ` N │ [icon] file │ lnum, col │ source line` — the ordinal, the aligned filename and
--- position columns in the same colours, and the source line with its file's treesitter colours. A plain file
--- list is ` N │ path`; a position-less list with descriptions ` N │ file │ description`. A grep entry that
--- knows where its match ends (`end_col`) marks the match.
---@param loclist_win integer?  a window handle → that window's location list; nil → the quickfix list
---@return table[] items
local function build_items(loclist_win)
    local cols = require("lvim-qf-loc.qf.edit").columns
    local raw = loclist_win and vim.fn.getloclist(loclist_win, { items = 0 }).items
        or vim.fn.getqflist({ items = 0 }).items
    raw = raw or {}
    local positioned = require("lvim-qf-loc.qf.edit").list_positioned(raw)
    local files = cols.list_is_files(raw)
    local cap = config.edit.max_filename_width
    local sep = " " .. config.edit.separator .. " "

    -- the entries the browser shows: the real ones (context rows, valid = 0, belong to the editable window)
    local entries = {}
    for i, e in ipairs(raw) do
        local path = (e.bufnr and e.bufnr > 0 and vim.api.nvim_buf_is_valid(e.bufnr))
                and vim.api.nvim_buf_get_name(e.bufnr)
            or ""
        if path ~= "" and (e.valid ~= 0 or not positioned) then
            entries[#entries + 1] = { e = e, path = path, idx = i }
        end
    end

    -- list-wide column widths, so every row lines up
    local ord_w, file_w, mid_w, sev_w = #tostring(math.max(1, #entries)), 0, 1, 0
    for _, x in ipairs(entries) do
        file_w = math.max(file_w, vim.fn.strdisplaywidth(cols.filename_of(x.e, cap)))
        mid_w = math.max(mid_w, vim.fn.strdisplaywidth(cols.mid_text(x.e)))
        sev_w = math.max(sev_w, vim.fn.strdisplaywidth(cols.icon_of(x.e)))
    end

    local cache = require("lvim-qf-loc.qf.filecache").new()
    local tcache = {}
    local items = {}
    for n, x in ipairs(entries) do
        local e = x.e
        local parts, spans = {}, {}
        local len = 0
        local function put(text, hl)
            parts[#parts + 1] = text
            if hl and #text > 0 then
                spans[#spans + 1] = { len, len + #text, hl }
            end
            len = len + #text
        end
        put(cols.lpad(tostring(n), ord_w), "LvimQfLocOrdinal")
        put(sep, "LvimQfLocSep")
        local body, body_hl
        if files then
            body, body_hl = cols.path_text(e), "LvimQfLocFile"
        elseif not positioned then
            put(cols.rpad(cols.filename_of(e, cap), file_w), "LvimQfLocFile")
            put(sep, "LvimQfLocSep")
            body = cols.description_text(e)
        else
            if sev_w > 0 then
                put(cols.rpad(cols.icon_of(e), sev_w), cols.sev_hl[e.type or ""] or "LvimQfLocSep")
            end
            put(cols.rpad(cols.filename_of(e, cap), file_w), "LvimQfLocFile")
            put(sep, "LvimQfLocSep")
            put(cols.lpad(cols.mid_text(e), mid_w), "LvimQfLocLnum")
            put(sep, "LvimQfLocSep")
            body = cols.source_text(e, cache)
        end
        body = (body or ""):gsub("[\r\n]+", " ")
        local locator = len
        put(body, body_hl)
        local match
        if positioned then
            if config.edit.syntax then
                for _, r in ipairs(cols.syntax_ranges(e, body, cols.ts_ctx(tcache, e.bufnr)) or {}) do
                    spans[#spans + 1] = { locator + r[1], locator + r[2], r[3] }
                end
            end
            -- the match a grep entry points at: col..end_col on its own line (1-based, end exclusive)
            local c0, c1 = (e.col or 0) - 1, (e.end_col or 0) - 1
            if c0 >= 0 and c1 > c0 and (e.end_lnum or 0) <= e.lnum and c1 <= #body then
                match = { { c0 = locator + c0, c1 = locator + c1 } }
            end
        end
        items[#items + 1] = {
            path = x.path,
            lnum = (e.lnum and e.lnum > 0) and e.lnum or 1,
            col = (e.col and e.col > 0) and e.col or 1,
            end_lnum = e.end_lnum,
            end_col = e.end_col,
            type = e.type or "",
            text = table.concat(parts),
            qf_idx = x.idx, -- its index in the list (]q / [q move the selection to it)
            qf_text = e.text, -- the entry's own text, kept when the rows go back to a quickfix list (`<C-q>`)
            -- what the row's text after the locator IS, for in-place editing (qf/area_edit.lua): a source line,
            -- a file path (→ rename), or a description (not editable)
            qf_edit = files and "path" or (positioned and "line" or nil),
            qf_entry = e,
            icon = "", -- the columns carry everything (no file icon, as in the editable list)
            hl_spans = spans,
            locator_bytes = locator,
            match_bytes = match,
        }
    end
    return items
end

--- Jump to an entry and centre it. `nvim_win_set_buf` (not `:edit`) so an unsaved editable preview can't block
--- the jump with E37.
---@param it table
local function jump(it)
    if not (it and it.path) then
        return
    end
    -- the list's current entry becomes this one, as `:cc` would make it (so ]q / [q go on from here)
    if it.qf_idx then
        if open_loclist and vim.api.nvim_win_is_valid(open_loclist) then
            pcall(vim.fn.setloclist, open_loclist, {}, "a", { idx = it.qf_idx })
        else
            pcall(vim.fn.setqflist, {}, "a", { idx = it.qf_idx })
        end
    end
    local buf = vim.fn.bufadd(it.path)
    local ok, err = pcall(vim.fn.bufload, buf)
    if not ok then
        vim.notify("lvim-qf-loc: cannot load " .. it.path .. ": " .. tostring(err), vim.log.levels.WARN)
        return
    end
    vim.api.nvim_win_set_buf(0, buf)
    vim.bo[buf].buflisted = true
    pcall(vim.api.nvim_win_set_cursor, 0, { it.lnum or 1, math.max(0, (it.col or 1) - 1) })
    vim.cmd("normal! zz")
end

--- The browser's own row keys: the view switch, and the list steps (]q / [q / ]l / [l). The steps are bound
--- HERE, on the list, because a picker panel is key-locked — every unbound printable key is a no-op, so the
--- global ]q never got past its `]` (and the following `q` then closed the browser). Bound by the panel, the
--- `]` is its own chord prefix and resolves the second key.
---@param loclist_win integer?
---@return table[]
browser_keys = function(loclist_win)
    local keys = {}
    if config.switch and config.switch ~= "" then
        keys[#keys + 1] = {
            key = config.switch,
            name = "native",
            run = function(_, close)
                -- AFTER the picker's own row-action handoff: run inside it, the swap's frame was painted by
                -- that handoff mid-way (a blank screen between the two views)
                vim.schedule(function()
                    require("lvim-qf-loc.qf.view").switch(loclist_win, close)
                end)
            end,
        }
    end
    -- the newer / older list of the history, from the query and the list alike (Ctrl keys type nothing): the
    -- browser is rebuilt on it
    local kind = loclist_win and "loc" or "qf"
    for _, m in ipairs({ { (config.step or {}).next, 1, "newer" }, { (config.step or {}).prev, -1, "older" } }) do
        if m[1] and m[1] ~= "" then
            keys[#keys + 1] = {
                key = m[1],
                name = m[3],
                keep_insert = true,
                run = function()
                    require("lvim-qf-loc.qf.view").cycle(kind, m[2], loclist_win)
                end,
            }
        end
    end
    -- the rows editable in place, as the native window always is (list only: in the query it is a typed key)
    local ek = config.browser.edit_key
    if ek and ek ~= "" then
        keys[#keys + 1] = {
            key = ek,
            name = "edit",
            mode = "n",
            run = function()
                require("lvim-qf-loc.qf.area_edit").open(open_handle, loclist_win)
            end,
        }
    end
    local jk = config.jump.enabled and config.jump.keys or {}
    for _, m in ipairs({ { jk.qf_next, "qf", 1 }, { jk.qf_prev, "qf", -1 }, { jk.loc_next, "loc", 1 }, { jk.loc_prev, "loc", -1 } }) do
        if m[1] and m[1] ~= "" then
            keys[#keys + 1] = {
                key = m[1],
                mode = "n", -- the list only: in the query a `]` is a typed character
                run = function()
                    for _ = 1, vim.v.count1 do
                        require("lvim-qf-loc.qf.jump").step(m[2], m[3])
                    end
                end,
            }
        end
    end
    return keys
end

--- Open the browser. `loclist_win` = a window handle for that window's location list, or nil for the quickfix
--- list. `layout` = "area" (default) | "float" | "bottom".
---@param loclist_win integer?
---@param layout string?
function M.open(loclist_win, layout)
    local ok, picker = pcall(require, "lvim-picker")
    if not ok then
        notify("lvim-picker is required for the browser.", vim.log.levels.WARN)
        return
    end
    local items = build_items(loclist_win)
    open_loclist = loclist_win
    -- the grep a list came from (lvim-picker keeps it in the list's context): its matches are marked in the
    -- preview too
    local grep = grep_of(loclist_win)
    if #items == 0 then
        notify("List is empty.", vim.log.levels.INFO)
        return
    end

    picker.open({
        -- its own dock identity (else it is derived from the title, the same as lvim-picker's own quickfix
        -- finder), so `M.close` can find it
        key = KEY,
        title = loclist_win and "Location List" or "Quickfix",
        title_pos = config.title_pos, -- alignment — ONE config value for every layout ("center" default)
        layout = layout or config.browser.layout,
        -- Forward OUR dock config to the picker per-call: `dock_stack` decides managed-stack vs. standalone, and
        -- `force` supplies the per-layout ANCHORED geometry overrides (deep-merged over the central dock geometry
        -- inside `dock.slot`). Both apply ONLY to this picker-based browser — the native qf window and the
        -- cursor-preview float stay content-fit and are untouched.
        dock_stack = config.dock.dock_stack,
        force = config.dock.force,
        items = items,
        format = function(it)
            return it.text
        end,
        preview_file = true, -- the REAL file buffer in the preview — no FFI, no internal scroll math
        match_pattern = type(grep.pattern) == "string" and grep.pattern or nil,
        regex = grep.regex == true,
        preview_side = config.browser.preview_side, -- "right" (default) | "left" | "dynamic" (peek float above)
        -- No `preview_heights`: the SLOT height of the picker's float/area/bottom dock is centralized by
        -- lvim-utils (`config.dock.geometry`). Passing our own would duplicate it, so we let the picker/surface
        -- derive it — this browser only chooses the layout and the preview SIDE, never the size.
        keys = browser_keys(loclist_win),
        subtitle = function(it)
            return vim.fn.fnamemodify(it.path, ":t")
        end,
        on_confirm = jump,
        on_open = function(handle)
            open_handle = handle
        end,
    })
end

--- Whether the browser is open.
---@return boolean
function M.is_open()
    return open_handle ~= nil and open_handle.is_open()
end

--- Put the cursor on the open browser's list (normal mode).
function M.focus_list()
    if open_handle and open_handle.is_open() and open_handle.focus_list then
        open_handle.focus_list()
    end
end

--- Move the open browser's selection to list entry `idx` (after ]q / [q). No-op when it is closed.
---@param idx integer
function M.sync(idx)
    if open_handle and open_handle.is_open() then
        open_handle.select(function(src)
            return type(src) == "table" and src.qf_idx == idx
        end)
    end
end

--- Show the CURRENT list in the open browser, in place (after a newer / older list was made current): its rows
--- and its grep pattern are swapped without closing the browser, so nothing flickers. false when the browser
--- is not open (the caller opens it instead).
---@param loclist_win integer?
---@return boolean
function M.refresh(loclist_win)
    if not (open_handle and open_handle.is_open() and open_handle.set_items) then
        return false
    end
    open_loclist = loclist_win
    local grep = grep_of(loclist_win)
    open_handle.set_items(build_items(loclist_win), {
        match_pattern = type(grep.pattern) == "string" and grep.pattern or false,
        regex = grep.regex == true,
    })
    return true
end

--- Close the browser if it is open (the view switch, run as a command while it shows).
function M.close()
    local okd, dock = pcall(require, "lvim-utils.dock")
    if okd and type(dock.entries) == "function" then
        for _, e in ipairs(dock.entries()) do
            if e.id == "lvim-picker:" .. KEY then
                dock.close(e.key)
            end
        end
    end
    local oks, source = pcall(require, "lvim-picker.source")
    if oks and type(source.close_active) == "function" then
        source.close_active() -- an un-docked open
    end
end

M._build_items = build_items -- internal test seam

return M
