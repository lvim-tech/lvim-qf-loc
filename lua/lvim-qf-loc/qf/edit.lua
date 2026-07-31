-- lua/lvim-qf-loc/qf/edit.lua
-- The EDITABLE quickfix, built to be CRASH-SAFE. The qf buffer's
-- editable text is the SOURCE LINE of each entry (read live from the file), and the `file:lnum │ ` prefix is
-- INLINE VIRTUAL TEXT, not buffer text — so there is no fragile delimiter to parse (the classic failure
-- of that approach: one deleted separator character aborts a whole file) and the prefix simply cannot be
-- broken by an edit. Each row's entry
-- identity rides on an EXTMARK (it tracks the line through reorders/inserts), never the text. On write we apply
-- the edits with full guards: every entry is verified to still match its source line on disk (external change →
-- skipped, not corrupted), conflicting edits to one line are reported, every buffer op is pcall'd, and the
-- changed files are saved per the autosave policy. No line-count changes (one row = one source line), so edits
-- never drift. A plain FILE list (position-less, no descriptions) instead makes each row the file's PATH —
-- editing it on `:w` RENAMES / MOVES the file (creates parent dirs, never overwrites, follows an open buffer).
--
---@module "lvim-qf-loc.qf.edit"

local api = vim.api
local config = require("lvim-qf-loc.config")
local filecache = require("lvim-qf-loc.qf.filecache")
local notify = require("lvim-qf-loc.utils.notify")
local context = require("lvim-qf-loc.qf.context")
-- The shared button/box model the band renders (never a hand-rolled highlight string).
local surface = require("lvim-ui.surface")
local preview = require("lvim-qf-loc.qf.preview")
local browser = require("lvim-qf-loc.qf.browser")

local M = {}

local NS = api.nvim_create_namespace("lvim-qf-loc-edit")
local NS_SYNTAX = api.nvim_create_namespace("lvim-qf-loc-edit-syntax") -- source treesitter highlights only
--- qbuf → { extmark_id → { path, lnum, col, bufnr, orig, entry } } — the entry behind each rendered row.
---@type table<integer, table<integer, table>>
local rows = {}

--- The editable source text for an entry: the live line of its file (a loaded buffer wins), else the entry's
--- own text as a read-only-ish fallback.
---@param e table  a quickfix item
---@param cache table
---@return string
local function source_text(e, cache)
    if e.bufnr and e.bufnr > 0 and e.lnum and e.lnum > 0 then
        local path = api.nvim_buf_is_valid(e.bufnr) and api.nvim_buf_get_name(e.bufnr) or ""
        if path ~= "" then
            local line = cache:line(e.bufnr, path, e.lnum)
            if line ~= nil then
                return line
            end
        end
    end
    return ((e.text or ""):gsub("[\r\n]+", " "))
end

--- Whether the list is POSITIONED — any real entry points at a file line (`lnum > 0`). Grep / diagnostics /
--- references are positioned; a plain file list (e.g. `:cexpr` paths) is not. Drives the 2-column layout +
--- whether context expand/collapse means anything.
---@param items table[]
---@return boolean
local function list_positioned(items)
    for _, e in ipairs(items) do
        if e.valid ~= 0 and e.lnum and e.lnum > 0 then
            return true
        end
    end
    return false
end
M.list_positioned = list_positioned

--- For a POSITION-LESS entry, the buffer text = its `text` as a description, but only when it adds something
--- (non-empty and not just the file path/name) — else "" so the row is a clean `ordinal │ file`.
---@param e table
---@return string
local function description_text(e)
    local path = (e.bufnr and e.bufnr > 0 and api.nvim_buf_is_valid(e.bufnr)) and api.nvim_buf_get_name(e.bufnr) or ""
    local txt = ((e.text or ""):gsub("^%s+", ""):gsub("[\r\n]+", " "))
    if
        txt == ""
        or txt == path
        or (path ~= "" and (txt == vim.fn.fnamemodify(path, ":~:.") or txt == vim.fn.fnamemodify(path, ":t")))
    then
        return " " -- a SPACE, not "" — vim falls back to its default `file|lnum| text` when a row is empty
    end
    return txt
end

--- For a FILE-list entry, the editable buffer text = its PATH relative to cwd (`~` for paths outside it).
--- Editing this path on `:w` renames / moves the file (see `apply_renames`).
---@param e table
---@return string
local function path_text(e)
    local name = (e.bufnr and e.bufnr > 0 and api.nvim_buf_is_valid(e.bufnr)) and api.nvim_buf_get_name(e.bufnr) or ""
    if name == "" then
        return " "
    end
    return vim.fn.fnamemodify(name, ":~:.")
end

--- A FILE list: position-less AND no entry carries a description beyond its path — so each row is simply a file
--- and its editable text is the PATH itself (→ rename / move on write), not a source line or a description.
---@param items table[]
---@return boolean
local function list_is_files(items)
    if #items == 0 or list_positioned(items) then
        return false
    end
    for _, e in ipairs(items) do
        if e.valid ~= 0 and description_text(e) ~= " " then
            return false -- a real description → keep the description view, not a rename list
        end
    end
    return true
end

--- `quickfixtextfunc`: render each entry's row. Positioned list → the entry's SOURCE LINE (the editable text);
--- position-less list → an optional description (the `ordinal │ file` rows have no editable source). vim calls
--- this to fill the qf buffer; the `file:lnum` prefix is added as virtual text afterwards (setup_buffer).
---@param info table  { quickfix, winid, id, start_idx, end_idx }
---@return string[]
function M.textfunc(info)
    local what = info.quickfix == 1 and vim.fn.getqflist({ id = info.id, items = 0 })
        or vim.fn.getloclist(info.winid, { id = info.id, items = 0 })
    local items = what.items or {}
    local positioned = list_positioned(items)
    local files = list_is_files(items)
    local cache = filecache.new()
    local out = {}
    for i = info.start_idx, info.end_idx do
        local e = items[i] or {}
        -- positioned → the editable SOURCE LINE; a plain file list → the editable PATH (rename); else a
        -- description. A SPACE, never "" — vim falls back to its default `file|lnum col| text` for an empty row.
        local txt = (positioned and source_text(e, cache)) or (files and path_text(e)) or description_text(e)
        out[#out + 1] = (txt ~= "") and txt or " "
    end
    return out
end

local SEV_HL =
    { E = "DiagnosticError", W = "DiagnosticWarn", I = "DiagnosticInfo", N = "DiagnosticHint", H = "DiagnosticHint" }

--- Right-pad `s` to `w` display cells (left-align the filename column).
---@param s string
---@param w integer
---@return string
local function rpad(s, w)
    local dw = vim.fn.strdisplaywidth(s)
    return dw >= w and s or (s .. string.rep(" ", w - dw))
end

--- Left-pad `s` to `w` display cells (right-align the line-number column).
---@param s string
---@param w integer
---@return string
local function lpad(s, w)
    local dw = vim.fn.strdisplaywidth(s)
    return dw >= w and s or (string.rep(" ", w - dw) .. s)
end

--- The entry's display filename: path relative to cwd/home, truncated (leading …) to `cap` cells.
---@param e table
---@param cap integer
---@return string
local function filename_of(e, cap)
    if not (e.bufnr and e.bufnr > 0 and api.nvim_buf_is_valid(e.bufnr)) then
        return ""
    end
    local path = api.nvim_buf_get_name(e.bufnr)
    if path == "" then
        return ""
    end
    path = vim.fn.fnamemodify(path, ":~:.")
    if cap and cap > 0 and vim.fn.strdisplaywidth(path) > cap then
        while vim.fn.strdisplaywidth(path) > cap - 1 do
            path = vim.fn.strcharpart(path, 1)
        end
        path = "…" .. path
    end
    return path
end

--- The middle column's text: `lnum, col` for ANY real entry that carries a column (`col > 0` — grep,
--- references, diagnostics at a position …), else just the line number (no meaningful column, or a context row).
---@param e table
---@return string
local function mid_text(e)
    if e.valid ~= 0 and (e.col or 0) > 0 then
        return ("%d, %d"):format(e.lnum or 0, e.col)
    end
    return tostring(e.lnum or 0)
end

--- The severity icon an entry draws, or "" when it carries no type. One place decides it, so the
--- WIDTH measured for the column and the text put in it can never disagree.
---@param e table
---@return string
local function icon_of(e)
    local t = e.type or ""
    if t == "" then
        return ""
    end
    return config.browser.icons[t] or config.browser.icons.default or ""
end

--- The inline virtual-text prefix: aligned `[icon] filename │ lnum,col │` columns — filename
--- blue, the middle line/col column yellow, the separators red. `col_width` / `mid_width` are the list-wide
--- maxima so every row lines up.
---@param e table
---@param col_width integer
---@param mid_width integer
---@param sev_width integer  the icon COLUMN's width in cells (0 = this list has no severities).
---   A width rather than a flag: the configured icons are not all the same size — `󰅚 ` is two
---   cells while `I`/`N`/`H` are a bare space — and an entry with no type at all draws nothing,
---   so every row must be padded to the SAME column or the filenames step left and right down
---   the list (reported from a screenshot).
---@param positioned boolean  the list points at file lines (→ the line/col column); else just `ordinal │ file`
---@param files boolean  a plain FILE list — the path is the editable buffer text, so draw NO filename prefix
---@return table[]
local function prefix_chunks(e, col_width, mid_width, sev_width, positioned, files)
    local sep = config.edit.separator
    -- A FILE list: the PATH is the editable buffer text — no virtual filename column (it would duplicate it).
    if files then
        return {}
    end
    -- a POSITION-LESS list with descriptions: a single filename column; the description is the buffer text.
    -- (vim marks no-lnum entries `valid = 0`; in a position-less list that is NOT a context row — context only
    -- exists in a positioned list.)
    if not positioned then
        return { { rpad(filename_of(e, config.edit.max_filename_width), col_width) .. " ", "LvimQfLocFile" } }
    end
    -- a CONTEXT row (valid = 0): blank filename column + the line number — sits under the real entry
    if e.valid == 0 then
        local chunks = {}
        if sev_width > 0 then
            chunks[#chunks + 1] = { string.rep(" ", sev_width), "LvimQfLocSep" }
        end
        chunks[#chunks + 1] = { rpad("", col_width), "LvimQfLocSep" }
        chunks[#chunks + 1] = { " " .. sep .. " ", "LvimQfLocSep" }
        chunks[#chunks + 1] = { lpad(mid_text(e), mid_width), "LvimQfLocLnum" }
        chunks[#chunks + 1] = { " " .. sep .. " ", "LvimQfLocSep" }
        return chunks
    end
    local chunks = {}
    if sev_width > 0 then
        chunks[#chunks + 1] = { rpad(icon_of(e), sev_width), SEV_HL[e.type or ""] or "LvimQfLocSep" }
    end
    chunks[#chunks + 1] = { rpad(filename_of(e, config.edit.max_filename_width), col_width), "LvimQfLocFile" }
    chunks[#chunks + 1] = { " " .. sep .. " ", "LvimQfLocSep" }
    chunks[#chunks + 1] = { lpad(mid_text(e), mid_width), "LvimQfLocLnum" }
    chunks[#chunks + 1] = { " " .. sep .. " ", "LvimQfLocSep" }
    return chunks
end

--- The treesitter language for a path (cached), or nil when there is no highlights query for it.
--- Keyed by the resolved FILETYPE, not the path: the language is a pure function of the filetype, so
--- caching per-path would grow without bound across a session that churns many files through grep
--- lists, while per-filetype is bounded by the (small, finite) number of distinct filetypes seen.
---@type table<string, string|false>
local _lang_cache = {}
---@param path string
---@return string?
local function lang_for(path)
    local ft = vim.filetype.match({ filename = path }) or ""
    if ft == "" then
        return nil
    end
    local cached = _lang_cache[ft]
    if cached ~= nil then
        return cached or nil
    end
    local lang = vim.treesitter.language.get_lang(ft) or ft ---@type string|false
    if lang and not vim.treesitter.query.get(lang, "highlights") then
        lang = false
    end
    _lang_cache[ft] = lang
    return lang or nil
end

--- The context-row DIM degree from `config.context.dim_amount` (0 = no dim … 1 = invisible), as the fraction of
--- the ORIGINAL colour to KEEP when blending toward the bg (so `1 - dim`, clamped).
---@return number
local function dim_keep()
    local a = config.context and config.context.dim_amount
    a = type(a) == "number" and a or 0.4
    return math.max(0, math.min(1, 1 - a))
end

--- A global DIMMED copy of a highlight group (fg blended toward the bg, exactly like lvim-colorscheme's dim
--- namespace), created lazily + cached. Context rows use these so they keep full syntax but read muted. The
--- cache is cleared on a colorscheme change (define_highlights), so the dim tracks the live palette.
---@type table<string, boolean>
local dim_cache = {}
---@param group string
---@return string
local function dim_group(group)
    local name = "LvimQfLocDim_" .. group
    if dim_cache[name] then
        return name
    end
    local okc, c = pcall(require, "lvim-utils.colors")
    local okh, hl = pcall(require, "lvim-utils.highlight")
    if not (okc and okh and c.bg) then
        return group -- no palette → leave it undimmed rather than break the colour
    end
    local src = api.nvim_get_hl(0, { name = group, link = false })
    local def = { italic = src.italic, bold = src.bold, underline = src.underline }
    if src.fg then
        -- nvim_get_hl returns fg as a 24-bit NUMBER; blend wants a "#rrggbb" string
        def.fg = hl.blend(("#%06x"):format(src.fg), c.bg, dim_keep())
    end
    pcall(api.nvim_set_hl, 0, name, def)
    dim_cache[name] = true
    return name
end

--- The treesitter context for a source buffer — `{ lang, parser, query }` — resolved ONCE per render and
--- memoised in `cache` (keyed by bufnr; `false` = no usable grammar). Hoisting this out of the per-row loop
--- means each source is parsed once per render, not re-resolved (get_parser + query.get + lang lookup) for
--- every one of its rows — the hot path when a big list (or the live Diagnostics list) re-renders.
---@param cache table<integer, table|false>
---@param bufnr integer?
---@return table|false ctx  { lang: string, parser: vim.treesitter.LanguageTree, query: vim.treesitter.Query }
local function ts_ctx(cache, bufnr)
    if not (bufnr and bufnr > 0) then
        return false
    end
    local hit = cache[bufnr]
    if hit ~= nil then
        return hit
    end
    ---@type table|false
    local ctx = false
    if api.nvim_buf_is_valid(bufnr) then
        local lang = lang_for(api.nvim_buf_get_name(bufnr))
        if lang then
            local ok, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
            local query = vim.treesitter.query.get(lang, "highlights")
            if ok and parser and query then
                ctx = { lang = lang, parser = parser, query = query }
            end
        end
    end
    cache[bufnr] = ctx
    return ctx
end

--- Apply the file's treesitter highlights to one rendered row, using the pre-resolved `ctx` for its source
--- buffer (`ts_ctx`). `dim` (context rows) routes every capture through its dimmed copy, so the code stays
--- coloured but muted. Returns whether treesitter was applicable (so the caller can fall back to a flat colour
--- when a file has no grammar).
---@param qbuf integer
---@param i integer  1-based row
---@param e table
---@param qline string  the rendered (source) line
---@param dim boolean
---@param ctx table|false  the row's source treesitter context, from `ts_ctx`
---@return boolean applied
local function highlight_line(qbuf, i, e, qline, dim, ctx)
    if not ctx or not (e.lnum and e.lnum > 0) then
        return false
    end
    local lang, parser, query = ctx.lang, ctx.parser, ctx.query
    local row, maxc = e.lnum - 1, #qline
    local okp, trees = pcall(function()
        return parser:parse({ row, row + 1 })
    end)
    if not (okp and trees) then
        return true -- treesitter applies; this row just failed to parse — don't fall back to a flat colour
    end
    for _, tree in ipairs(trees) do
        for id, node in query:iter_captures(tree:root(), e.bufnr, row, row + 1) do
            local sr, sc, er, ec = node:range()
            if sr == row then -- only this row; clamp to the qf line's bytes
                local c0 = math.min(sc, maxc)
                local c1 = (er == row) and math.min(ec, maxc) or maxc
                if c1 > c0 then
                    local g = "@" .. query.captures[id] .. "." .. lang
                    pcall(api.nvim_buf_set_extmark, qbuf, NS_SYNTAX, i - 1, c0, {
                        end_col = c1,
                        hl_group = dim and dim_group(g) or g,
                        priority = 90,
                    })
                end
            end
        end
    end
    return true
end

--- Syntax-highlight every rendered row from its file's treesitter grammar. Real entries get
--- full colour; CONTEXT rows (valid = 0) get the SAME syntax routed through DIMMED copies (the lvim-colorscheme
--- `dim` look), so context reads as muted code — not a flat block, not another match. Colours come from each
--- source buffer's PERSISTENT parser (NOT a per-line `get_string_parser`, which churns native trees and has
--- corrupted neovim's heap). The qf line is the source line, so columns map 1:1.
---@param qbuf integer
---@param items table[]
local function apply_source_highlights(qbuf, items)
    if not (config.edit.syntax and api.nvim_buf_is_valid(qbuf)) then
        return
    end
    local qlines = api.nvim_buf_get_lines(qbuf, 0, -1, false)
    local tcache = {} -- bufnr → treesitter context, resolved once per render (see ts_ctx)
    for i, e in ipairs(items) do
        local qline = qlines[i]
        if qline and qline ~= "" then
            local is_ctx = e.valid == 0
            if not highlight_line(qbuf, i, e, qline, is_ctx, ts_ctx(tcache, e.bufnr)) and is_ctx then
                -- a context line from a file with no treesitter grammar → one flat muted colour
                pcall(api.nvim_buf_set_extmark, qbuf, NS_SYNTAX, i - 1, 0, {
                    end_col = #qline,
                    hl_group = "LvimQfLocContext",
                    priority = 90,
                })
            end
        end
    end
end

--- Register the list column highlight groups (filename = blue, separators = red) from the lvim-utils palette;
--- link-based fallback when it is absent. The line number follows the editor's `LineNr` (real-buffer gutter
--- colour), so it is not registered here. Re-applied on a colorscheme/palette change.
local function define_highlights()
    for k in pairs(dim_cache) do -- the dimmed context copies are palette-derived; recompute on a theme change
        dim_cache[k] = nil
    end
    local okc, c = pcall(require, "lvim-utils.colors")
    local okh, hl = pcall(require, "lvim-utils.highlight")
    if okc and okh and c.blue then
        hl.register({
            LvimQfLocFile = { fg = c.blue },
            LvimQfLocLnum = { fg = c.yellow }, -- the middle line/col column
            LvimQfLocSep = { fg = c.red },
            LvimQfLocCursorLine = { bg = hl.blend(c.blue, c.bg, 0.2) }, -- the active row, a blue tint
            -- context rows (zo/zc): a single muted colour so they read as background, not as matches
            LvimQfLocContext = { fg = c.comment or hl.blend(c.fg, c.bg, 0.5), italic = true },
            -- the panel's top bar (a key-button bar, modern-view style): the bar bg + the brighter key box +
            -- the label, the lvim-utils tint canon (key 0.4, bar/label 0.2).
            LvimQfLocWinbar = { fg = c.blue, bg = hl.blend(c.blue, c.bg, 0.2) },
            LvimQfLocBarKey = { fg = c.blue, bg = hl.blend(c.blue, c.bg, 0.4), bold = true },
            LvimQfLocBarLabel = { fg = c.yellow, bg = hl.blend(c.yellow, c.bg, 0.2) }, -- the label: yellow on a yellow tint
        })
    else
        for name, link in pairs({
            LvimQfLocFile = "Directory",
            LvimQfLocLnum = "WarningMsg",
            LvimQfLocSep = "ErrorMsg",
            LvimQfLocCursorLine = "CursorLine",
            LvimQfLocContext = "Comment",
        }) do
            pcall(api.nvim_set_hl, 0, name, { link = link, default = true })
        end
    end
end

--- Prepare the qf buffer for editing: make it modifiable, lay the virtual prefixes + one entry-tracking
--- extmark per row, and install the write handler. Re-run after an apply (the source lines changed).
---@param qbuf integer
---@param loclist_win integer?
---@type fun(qbuf: integer, owner_win: integer?, mode: string)  forward declaration: the band's buttons run
--- the same open the keys do, and the band is built in `decorate`, which comes first in the file.
local open_entry

---@type table<integer, table>  the live button BAND per window showing a qf buffer (see `lvim-ui.band`)
local bands = {}

--- How many REAL entries the list holds — what the band reports. A positioned list counts only its
--- valid entries (context rows are valid = 0); a position-less list's entries are all valid = 0, so
--- every one counts.
---@param loclist_win integer?
---@return integer
local function count_of(loclist_win)
    local what = loclist_win and vim.fn.getloclist(loclist_win, { items = 0 }) or vim.fn.getqflist({ items = 0 })
    local list = what.items or {}
    local positioned = list_positioned(list)
    if not positioned then
        return #list
    end
    local n = 0
    for _, e in ipairs(list) do
        if e.valid ~= 0 then
            n = n + 1
        end
    end
    return n
end

--- The window a qf entry opens INTO — the one the list was called from, remembered per buffer by
--- `setup_buffer` (a band button runs long after that, so it cannot close over the value).
---@param qbuf integer
---@return integer?
local function owner_of(qbuf)
    local w = vim.b[qbuf] and vim.b[qbuf].lvim_qf_loc_owner
    if w and w ~= 0 and api.nvim_win_is_valid(w) then
        return w
    end
    return nil
end

local function decorate(qbuf, loclist_win)
    if not api.nvim_buf_is_valid(qbuf) then
        return
    end
    vim.bo[qbuf].modifiable = true -- re-assert (this runs deferred, AFTER vim re-locks the qf buffer post-FileType)
    local what = loclist_win and vim.fn.getloclist(loclist_win, { items = 0 }) or vim.fn.getqflist({ items = 0 })
    local items = what.items or {}
    api.nvim_buf_clear_namespace(qbuf, NS, 0, -1)
    api.nvim_buf_clear_namespace(qbuf, NS_SYNTAX, 0, -1)
    -- list-wide column widths + whether the list carries severities (→ icon column) / file positions (→ the
    -- line/col column + context); position-less lists drop the line/col column entirely
    local positioned = list_positioned(items)
    local files = list_is_files(items)
    local col_width, mid_width, sev_width = 0, 1, 0
    for _, e in ipairs(items) do
        sev_width = math.max(sev_width, vim.fn.strdisplaywidth(icon_of(e)))
        if e.valid ~= 0 then
            col_width = math.max(col_width, vim.fn.strdisplaywidth(filename_of(e, config.edit.max_filename_width)))
        end
        if positioned then
            mid_width = math.max(mid_width, vim.fn.strdisplaywidth(mid_text(e)))
        end
    end
    local map = {}
    local n = api.nvim_buf_line_count(qbuf)
    for i, e in ipairs(items) do
        if i <= n then
            local line = api.nvim_buf_get_lines(qbuf, i - 1, i, false)[1] or ""
            local ok, id = pcall(api.nvim_buf_set_extmark, qbuf, NS, i - 1, 0, {
                virt_text = prefix_chunks(e, col_width, mid_width, sev_width, positioned, files),
                virt_text_pos = "inline",
                right_gravity = false,
            })
            if ok then
                local path = (e.bufnr and e.bufnr > 0 and api.nvim_buf_is_valid(e.bufnr))
                        and api.nvim_buf_get_name(e.bufnr)
                    or ""
                map[id] = { path = path, lnum = e.lnum or 0, col = e.col, bufnr = e.bufnr, orig = line, entry = e }
                -- colour the editable PATH like a filename (no source highlights on a file list)
                if files and #line > 0 then
                    pcall(api.nvim_buf_set_extmark, qbuf, NS_SYNTAX, i - 1, 0, {
                        end_col = #line,
                        hl_group = "LvimQfLocFile",
                    })
                end
            end
        end
    end
    rows[qbuf] = map
    -- The ordinal (sequence) gutter: ` N │ ` — the result number like a buffer's line-number column: `LineNr`
    -- for normal rows, `CursorLineNr` for the ACTIVE row (`v:relnum == 0`), then the red separator.
    local ord_w = #tostring(math.max(1, n))
    local stc = "%{% v:relnum == 0 ? '%#CursorLineNr#' : '%#LineNr#' %} %{printf('%"
        .. ord_w
        .. "d', v:lnum)} %#LvimQfLocSep#"
        .. config.edit.separator
        .. " "
    -- the panel's top bar: the key buttons left, the entry count right. A positioned list counts only its real
    -- entries (context rows are valid = 0); a position-less list's entries are all valid = 0, so count them all.
    local nitems = positioned and 0 or #items
    if positioned then
        for _, e in ipairs(items) do
            if e.valid ~= 0 then
                nitems = nitems + 1
            end
        end
    end
    local ekeys, ckeys = config.edit.keys or {}, config.context.keys or {}
    -- The panel's top bar. It is a real, FOCUSABLE band (`lvim-ui.band`) rather than the `winbar` STRING it
    -- used to be: a winbar cannot take a cursor, so its buttons were a legend and `<C-k>` fell through to
    -- whatever moves windows — the list lost focus instead of stepping into the bar, unlike every other
    -- panel in the set. The band sits on the same winbar ROW (so it still costs the list no line) and is a
    -- sector: `<C-k>` enters it, `h`/`l` pick a button, `<CR>` runs it, `<C-j>`/`q` step back to the list.
    local specs = {
        {
            ekeys.open,
            "open",
            function()
                open_entry(qbuf, owner_of(qbuf), "edit")
            end,
        },
        {
            ekeys.vsplit,
            "vsplit",
            function()
                open_entry(qbuf, owner_of(qbuf), "vsplit")
            end,
        },
        {
            ekeys.split,
            "split",
            function()
                open_entry(qbuf, owner_of(qbuf), "split")
            end,
        },
        {
            ekeys.tab,
            "tab",
            function()
                open_entry(qbuf, owner_of(qbuf), "tab")
            end,
        },
    }
    if positioned then -- context only means something with file positions
        specs[#specs + 1] = {
            ckeys.expand,
            "expand",
            function()
                context.expand(loclist_win)
            end,
        }
        specs[#specs + 1] = {
            ckeys.collapse,
            "collapse",
            function()
                context.collapse(loclist_win)
            end,
        }
    end
    specs[#specs + 1] = {
        ekeys.help,
        "keys",
        function()
            require("lvim-qf-loc.qf.help").show()
        end,
    }
    local items = {}
    for _, b in ipairs(specs) do
        if b[1] and b[1] ~= "" then
            items[#items + 1] = surface.button({
                name = b[2],
                key = (b[1]:gsub("^<(.*)>$", "%1")),
                style = "action",
                run = b[3],
            }, "action")
        end
    end
    for _, win in ipairs(api.nvim_list_wins()) do
        if api.nvim_win_get_buf(win) == qbuf then
            pcall(function()
                vim.wo[win].statuscolumn = stc
                -- `cursorline` is what makes the gutter REDRAW as the cursor moves (so the active row's
                -- `CursorLineNr` reverts to `LineNr` when you leave it); "both" also tints the active line via
                -- our blue `LvimQfLocCursorLine` (mapped through winhighlight, window-local).
                vim.wo[win].cursorline = true
                vim.wo[win].cursorlineopt = "both"
                vim.wo[win].winhighlight = "CursorLine:LvimQfLocCursorLine"
                vim.wo[win].colorcolumn = "" -- no vertical colour column in the list
                vim.wo[win].cursorcolumn = false
                -- clear the native qf window's default statusline (`[Quickfix List] …`) so it falls back to
                -- the user's global (chrome) statusline instead of vim's plain qf one
                vim.wo[win].statusline = ""
            end)
            -- Re-attach the band when this window has none (a fresh `:copen`), else just repaint it: the
            -- entry count and the context buttons change with every re-render, the window does not.
            -- A live entry IS a live band: the band clears its own slot from `on_close`, which fires when
            -- the host window closes, so there is nothing else to test.
            local band = bands[win]
            if band then
                -- Only the items: the suffix is a live closure installed at attach, so the count follows
                -- the list without being handed over on every repaint.
                band.set(items)
            else
                band = require("lvim-ui.winband").attach(win, {
                    items = items,
                    align = "left",
                    -- The band rides the WINBAR row, so the list keeps every one of its lines.
                    side = "top",
                    -- Bound by the band on the qf buffer itself: buffer-local is what makes it beat the
                    -- global window-navigation `<C-k>`, which is why the bar used to be unreachable.
                    enter_key = "<C-k>",
                    -- One more `<C-k>` inside the band continues out of the panel, to the window above.
                    nav_through = function()
                        pcall(vim.cmd, "wincmd k")
                    end,
                    -- The count is computed at PAINT time, not captured: the band outlives any one
                    -- render, and a closure over this pass's number would freeze the first count it saw.
                    suffix = function()
                        return " " .. count_of(loclist_win) .. " items "
                    end,
                    on_close = function()
                        bands[win] = nil
                    end,
                })
                if band then
                    bands[win] = band
                end
            end
        end
    end
    -- syntax-highlight the source text after the rows are laid (deferred so the list shows instantly)
    vim.schedule(function()
        if api.nvim_buf_is_valid(qbuf) then
            apply_source_highlights(qbuf, items)
        end
    end)
end

--- The autosave policy for a freshly-applied file buffer: "unmodified" saves only files that were NOT already
--- dirty before our edit; true always saves; false never. Guarded.
---@param buf integer
---@param was_modified boolean
local function autosave(buf, was_modified)
    local policy = config.edit.autosave
    if policy == false then
        return
    end
    if policy == "unmodified" and was_modified then
        return -- the user already had unsaved changes here — don't touch the file
    end
    pcall(api.nvim_buf_call, buf, function()
        vim.cmd("silent keepalt noautocmd update")
    end)
end

--- Write a set of per-file, per-line changes to disk — the shared, crash-safe core used by both the editable
--- buffer and search&replace. `changes[path][lnum] = { new, orig }`: a line is written ONLY when the file's
--- current text still equals `orig` (external change → skipped, never clobbered); every op is guarded; touched
--- files are saved per the autosave policy.
---@param changes table<string, table<integer, table>>
---@return integer applied, integer skipped
function M.apply_changes(changes)
    local applied, skipped = 0, 0
    for path, perline in pairs(changes) do
        local buf = vim.fn.bufadd(path)
        local ok_load = pcall(vim.fn.bufload, buf)
        if ok_load and api.nvim_buf_is_loaded(buf) then
            local was_modified = vim.bo[buf].modified
            local touched = false
            for lnum, ch in pairs(perline) do
                local cur = api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1]
                if cur == ch.orig then -- the file still matches what we showed → safe to write
                    if pcall(api.nvim_buf_set_lines, buf, lnum - 1, lnum, false, { ch.new }) then
                        applied, touched = applied + 1, true
                    else
                        skipped = skipped + 1
                    end
                else
                    skipped = skipped + 1 -- changed on disk / in another buffer since we rendered
                end
            end
            if touched then
                autosave(buf, was_modified)
            end
        else
            skipped = skipped + 1
        end
    end
    return applied, skipped
end

--- Force any OPEN quickfix/location window to re-read its (now-changed) source lines and refresh the editable
--- extmarks — called after an out-of-buffer mutation like search&replace.
---@param loclist_win integer?
function M.rerender(loclist_win)
    local items = loclist_win and vim.fn.getloclist(loclist_win, { items = 0 }).items
        or vim.fn.getqflist({ items = 0 }).items
    if loclist_win then
        vim.fn.setloclist(loclist_win, {}, "r", { items = items })
    else
        vim.fn.setqflist({}, "r", { items = items })
    end
    for _, win in ipairs(api.nvim_list_wins()) do
        local b = api.nvim_win_get_buf(win)
        if api.nvim_buf_is_valid(b) and vim.bo[b].buftype == "quickfix" then
            vim.schedule(function()
                if api.nvim_buf_is_valid(b) then
                    decorate(b, loclist_win)
                end
            end)
        end
    end
end

--- Rename / move each file whose path row was edited (a FILE list). Crash-safe: never overwrites an existing
--- target (skipped), creates the new path's parent dirs, and renames an open buffer to follow.
---@param renames table[]  { { old = string, new = string, bufnr = integer? }, ... }
---@return integer applied, integer skipped
local function apply_renames(renames)
    local applied, skipped = 0, 0
    for _, r in ipairs(renames) do
        if r.old ~= "" and r.new ~= "" and r.old ~= r.new then
            if vim.fn.filereadable(r.new) == 1 or vim.fn.isdirectory(r.new) == 1 then
                skipped = skipped + 1 -- target exists → never overwrite
            else
                pcall(vim.fn.mkdir, vim.fn.fnamemodify(r.new, ":h"), "p") -- create the target's parent dirs
                if vim.fn.rename(r.old, r.new) == 0 then
                    applied = applied + 1
                    if r.bufnr and r.bufnr > 0 and api.nvim_buf_is_valid(r.bufnr) then
                        local was_mod = vim.bo[r.bufnr].modified
                        if pcall(api.nvim_buf_set_name, r.bufnr, r.new) and not was_mod then
                            pcall(function()
                                vim.bo[r.bufnr].modified = false
                            end)
                        end
                    end
                else
                    skipped = skipped + 1
                end
            end
        end
    end
    return applied, skipped
end

--- Apply the buffer's edits back to the source files, then re-render. Crash-safe: each edit is only written
--- when the file's current line still equals what we rendered (external change → skipped); conflicting edits
--- to one line are reported; every file op is guarded. A FILE list renames/moves files instead (apply_renames).
---@param qbuf integer
---@param loclist_win integer?
local function apply(qbuf, loclist_win)
    local map = rows[qbuf] or {}
    local lines = api.nvim_buf_get_lines(qbuf, 0, -1, false)
    local what = loclist_win and vim.fn.getloclist(loclist_win, { items = 0 }) or vim.fn.getqflist({ items = 0 })

    -- A FILE list: every row is the file's PATH — applying it RENAMES / MOVES the file to the edited path.
    if list_is_files(what.items or {}) then
        local renames = {}
        for _, m in ipairs(api.nvim_buf_get_extmarks(qbuf, NS, 0, -1, {})) do
            local data = map[m[1]]
            local new = lines[m[2] + 1]
            if data and data.path ~= "" and new ~= nil then
                new = (new:gsub("^%s+", ""):gsub("%s+$", "")) -- trim
                if new ~= "" and new ~= data.orig then
                    renames[#renames + 1] = { old = data.path, new = vim.fn.fnamemodify(new, ":p"), bufnr = data.bufnr }
                end
            end
        end
        local applied, skipped = apply_renames(renames)
        vim.bo[qbuf].modified = false
        vim.bo[qbuf].modifiable = true
        decorate(qbuf, loclist_win)
        if applied > 0 or skipped > 0 then
            notify(
                ("Renamed %d file(s)%s."):format(applied, skipped > 0 and (", skipped " .. skipped) or ""),
                vim.log.levels.INFO
            )
        end
        return
    end

    -- gather edits per file: changes[path] = { [lnum] = { new, orig, bufnr } }
    local changes, conflicts, conflicted = {}, {}, {}
    for _, m in ipairs(api.nvim_buf_get_extmarks(qbuf, NS, 0, -1, {})) do
        local id, lrow = m[1], m[2]
        local data = map[id]
        local new = lines[lrow + 1]
        if data and data.path ~= "" and new ~= nil and new ~= data.orig then
            local key = data.path .. "\0" .. tostring(data.lnum)
            changes[data.path] = changes[data.path] or {}
            local prev = changes[data.path][data.lnum]
            if conflicted[key] then
                -- a third+ row for an already-conflicted line: never resurrect an edit for it
                changes[data.path][data.lnum] = nil
            elseif prev and prev.new ~= new then
                -- two rows disagree on the same source line: report it AND drop the first edit, so the
                -- warning ("conflicts: …") truthfully means the line was left untouched — not silently
                -- written with whichever row happened to enumerate first.
                conflicts[#conflicts + 1] = ("%s:%d"):format(data.path, data.lnum)
                conflicted[key] = true
                changes[data.path][data.lnum] = nil
            else
                changes[data.path][data.lnum] = { new = new, orig = data.orig, bufnr = data.bufnr }
            end
        end
    end
    local applied, skipped = M.apply_changes(changes)
    vim.bo[qbuf].modified = false
    -- re-render the qf from the now-updated sources (refresh the rows + their orig baselines)
    vim.bo[qbuf].modifiable = true
    decorate(qbuf, loclist_win)
    if #conflicts > 0 then
        notify(
            ("Applied %d, skipped %d; conflicts: %s"):format(applied, skipped, table.concat(conflicts, ", ")),
            vim.log.levels.WARN
        )
    elseif applied > 0 or skipped > 0 then
        notify(
            ("Applied %d edit(s)%s."):format(applied, skipped > 0 and (", skipped " .. skipped) or ""),
            vim.log.levels.INFO
        )
    end
end

--- The quickfix entry rendered on buffer line `line` (1-based), via that row's extmark — robust to edits /
--- reorders. nil when the line has no entry.
---@param qbuf integer
---@param line integer
---@return table?
function M.entry_at(qbuf, line)
    local map = rows[qbuf] or {}
    local marks = api.nvim_buf_get_extmarks(qbuf, NS, { line - 1, 0 }, { line - 1, -1 }, {})
    for _, m in ipairs(marks) do
        if map[m[1]] and map[m[1]].entry then
            return map[m[1]].entry
        end
    end
    return nil
end

--- Can this window HOST an opened file? A REAL editor window — not a float, and carrying a normal (listed-file)
--- buffer, i.e. `buftype == ""`. This rejects the quickfix / location list AND every side panel (neo-tree,
--- Outline, terminal, a `nofile` scratch …): dropping the file into any of those was the "it lands in the wrong
--- window / on top of the qf" bug — the old check only skipped `buftype == "quickfix"`.
---@param w integer?
---@return boolean
local function is_normal(w)
    return w ~= nil
        and api.nvim_win_is_valid(w)
        and api.nvim_win_get_config(w).relative == ""
        and vim.bo[api.nvim_win_get_buf(w)].buftype == ""
end

--- The first NORMAL editor window to host the opened file, or nil when only special windows (panels / the
--- quickfix) are open.
---@return integer?
local function fallback_win()
    for _, w in ipairs(api.nvim_list_wins()) do
        if is_normal(w) then
            return w
        end
    end
    return nil
end

--- Open the entry under the cursor. `mode` = "edit" | "vsplit" | "split" | "tab". Non-tab modes target the
--- window the quickfix was called from (`owner_win`), falling back to any normal window.
---@param qbuf integer
---@param owner_win integer?
---@param mode string
function open_entry(qbuf, owner_win, mode)
    local qf_win = api.nvim_get_current_win() -- the open key fired IN the quickfix window
    local entry = M.entry_at(qbuf, api.nvim_win_get_cursor(0)[1])
    if not (entry and entry.bufnr and entry.bufnr > 0 and api.nvim_buf_is_valid(entry.bufnr)) then
        return
    end
    pcall(vim.fn.bufload, entry.bufnr)
    local scratch -- the empty buffer `topleft new` makes (fallback only); wipe it once the file takes its window
    if mode == "tab" then
        pcall(vim.cmd, "tabnew")
    else
        -- Host the file in a REAL editor window: the one the qf was called from IF it is still one (it can go
        -- stale — closed, or now holding a panel), else any normal window. With NONE (only side panels + the
        -- quickfix), open a FRESH full-width window at the top for the file so the quickfix + panels stay put.
        -- (`aboveleft split` of the quickfix is E36 — its height is winfixheight-locked — and loading the file
        -- into the quickfix window itself would clobber the list, which was the reported bug. `topleft new` takes
        -- room from a FLEXIBLE window instead.)
        -- Host the file in the window the user came into the quickfix FROM: its LIVE alternate (`winnr("#")`,
        -- the window focused just before this jump). `owner_win` — captured ONCE when the list was built — is only
        -- a fallback, because it goes STALE: after navigating between windows and back it can point to a CLOSED
        -- window, which then fell through to the arbitrary FIRST window (the reported wrong-split). Then any normal
        -- window; then (handled below) a fresh split.
        local alt = vim.fn.win_getid(vim.fn.winnr("#"))
        local target = (alt ~= qf_win and is_normal(alt) and alt)
            or (is_normal(owner_win) and owner_win)
            or fallback_win()
        if target then
            api.nvim_set_current_win(target)
            if mode == "vsplit" then
                pcall(vim.cmd, "vsplit")
            elseif mode == "split" then
                pcall(vim.cmd, "split")
            end
        elseif pcall(vim.cmd, "topleft new") then
            scratch = api.nvim_get_current_buf()
        end
    end
    -- SAFETY NET: never load the file into the quickfix window itself — if a split could not be made and we still
    -- sit on it, bail rather than overwrite the list (the reported bug). `nvim_win_set_buf` (not `:edit`) so an
    -- unsaved buffer in the destination can't block the jump with E37.
    local dest = api.nvim_get_current_win()
    if dest == qf_win then
        return
    end
    api.nvim_win_set_buf(dest, entry.bufnr)
    vim.bo[entry.bufnr].buflisted = true
    if scratch and scratch ~= entry.bufnr and api.nvim_buf_is_valid(scratch) then
        pcall(api.nvim_buf_delete, scratch, { force = false })
    end
    local lnum = (entry.lnum and entry.lnum > 0) and entry.lnum or 1 -- a file pick has lnum 0 → top of file
    pcall(api.nvim_win_set_cursor, dest, { lnum, math.max(0, (entry.col or 1) - 1) })
    pcall(api.nvim_win_call, dest, function()
        vim.cmd("normal! zz")
    end)
end

--- Sync each entry's `text` field to its displayed SOURCE LINE. The renderer shows the source line via
--- `quickfixtextfunc`, but quickfix TOOLS (`:Cfilter` / `:Lfilter`, …) match the raw `text` field — so on a
--- diagnostics list (text = the message) `:Cfilter /local/` matched the hidden messages, not the visible code,
--- and wiped everything. Aligning the data with the display makes those tools filter on what you actually see.
--- Idempotent (a grep list already matches) and metadata-preserving (title + context kept).
---@param loclist_win integer?
local function sync_entry_text(loclist_win)
    local what = loclist_win and vim.fn.getloclist(loclist_win, { items = 0, title = 0, context = 0 })
        or vim.fn.getqflist({ items = 0, title = 0, context = 0 })
    local items = what.items or {}
    local cache = filecache.new()
    local changed = false
    for _, e in ipairs(items) do
        local src = source_text(e, cache)
        if src ~= "" and e.text ~= src then
            e.text = src
            changed = true
        end
    end
    if changed then
        local list = { items = items, title = what.title, context = what.context }
        if loclist_win then
            vim.fn.setloclist(loclist_win, {}, "r", list)
        else
            vim.fn.setqflist({}, "r", list)
        end
    end
end

--- Wire a quickfix/location buffer for editing (called from the FileType qf autocmd).
---@param qbuf integer
function M.setup_buffer(qbuf)
    if not config.edit.enabled or not api.nvim_buf_is_valid(qbuf) then
        return
    end
    local loclist_win
    local info = vim.fn.getloclist(0, { filewinid = 0 })
    if info.filewinid and info.filewinid ~= 0 then
        loclist_win = api.nvim_get_current_win()
    end
    -- align each entry's `text` with the shown source line so `:Cfilter` et al. match. DEFERRED: this hook can
    -- itself run inside a `setqflist` (e.g. DiagnosticChanged → reload → setqflist → FileType qf), and calling
    -- `setqflist` again from within would be E952 recursive. On the next tick we are outside that autocmd; the
    -- `changed` guard makes a re-fire converge (once synced, nothing to do).
    vim.schedule(function()
        if api.nvim_buf_is_valid(qbuf) then
            sync_entry_text(loclist_win)
        end
    end)
    vim.bo[qbuf].modifiable = true
    -- the native qf buffer has no name, so `:w` would E32 before our BufWriteCmd can run — give it one
    pcall(api.nvim_buf_set_name, qbuf, "quickfix-" .. qbuf)
    context.setup_keys(qbuf, loclist_win) -- the context expand/collapse keys
    -- the window the qf was called FROM (its alternate window now that the qf is focused) — open targets it
    local owner_win = vim.fn.win_getid(vim.fn.winnr("#"))
    if owner_win == 0 or not api.nvim_win_is_valid(owner_win) or owner_win == api.nvim_get_current_win() then
        owner_win = nil
    end
    local keys = config.edit.keys or {}
    local function map_open(lhs, mode)
        if lhs and lhs ~= "" then
            vim.keymap.set("n", lhs, function()
                open_entry(qbuf, owner_win, mode)
            end, { buffer = qbuf, nowait = true, silent = true, desc = "lvim-qf-loc: open (" .. mode .. ")" })
        end
    end
    map_open(keys.open, "edit")
    map_open(keys.vsplit, "vsplit")
    map_open(keys.split, "split")
    map_open(keys.tab, "tab")
    if keys.help and keys.help ~= "" then
        vim.keymap.set("n", keys.help, function()
            require("lvim-qf-loc.qf.help").show()
        end, { buffer = qbuf, nowait = true, silent = true, desc = "lvim-qf-loc: keymaps" })
    end
    -- C-d / C-u scroll the floating PREVIEW (peek more context) from the list, instead of the list itself
    if config.preview.enabled then
        for _, m in ipairs({ { config.preview.scroll_down or "<C-d>", 1 }, { config.preview.scroll_up or "<C-u>", -1 } }) do
            if m[1] and m[1] ~= "" then
                vim.keymap.set("n", m[1], function()
                    preview.scroll(m[2])
                end, {
                    buffer = qbuf,
                    nowait = true,
                    silent = true,
                    desc = "lvim-qf-loc: scroll preview",
                })
            end
        end
    end
    -- Editing is LINE-LOCKED: one row = one entry, so the actions that change the ROW COUNT are blocked — `o`/`O`
    -- (open line) and insert `<CR>`/`<C-m>`/`<C-j>` (newline) ADD a row; `dd` (delete line) and `J`/`gJ` (join)
    -- REMOVE one. You can still edit the source text in place; the count never drifts, which is exactly what the
    -- editable apply relies on. (Rare multi-line ops like `dj` aren't mapped, but the apply is extmark-based, so
    -- it only writes the real entries and never corrupts files on a stray drift.)
    for _, lhs in ipairs({ "o", "O", "dd", "J", "gJ" }) do
        vim.keymap.set("n", lhs, "<Nop>", { buffer = qbuf, nowait = true, silent = true })
    end
    for _, lhs in ipairs({ "<CR>", "<C-m>", "<C-j>" }) do
        vim.keymap.set("i", lhs, "<Nop>", { buffer = qbuf, silent = true })
    end
    vim.schedule(function()
        if api.nvim_buf_is_valid(qbuf) then
            decorate(qbuf, loclist_win)
        end
    end)
    local group = api.nvim_create_augroup("LvimQfLocEdit_" .. qbuf, { clear = true })
    -- Keep the cursor ON the match COLUMN (the one the middle `line, col` names) within the shown source line as
    -- you move between entries — not at the start of the line. Snap only on a ROW change, so moving horizontally
    -- to edit isn't fought; re-entrant CursorMoved from our own set is a no-op (same row).
    local last_snap_row
    local function snap_col()
        if not api.nvim_buf_is_valid(qbuf) then
            return
        end
        local win = api.nvim_get_current_win()
        if api.nvim_win_get_buf(win) ~= qbuf then
            return
        end
        local row = api.nvim_win_get_cursor(win)[1]
        if row == last_snap_row then
            return
        end
        last_snap_row = row
        local entry = M.entry_at(qbuf, row)
        if entry and entry.col and entry.col > 0 then
            local l = api.nvim_buf_get_lines(qbuf, row - 1, row, false)[1] or ""
            pcall(api.nvim_win_set_cursor, win, { row, math.min(entry.col - 1, #l) })
        end
    end
    api.nvim_create_autocmd("CursorMoved", { group = group, buffer = qbuf, callback = snap_col })
    vim.schedule(snap_col) -- initial position (runs after the deferred decorate has filled the row map)
    api.nvim_create_autocmd("BufWriteCmd", {
        group = group,
        buffer = qbuf,
        callback = function()
            -- acknowledge the "write" now (so :w doesn't E32/E37) and DEFER the apply: file edits are blocked
            -- by textlock inside a BufWriteCmd, so they must run on the next tick, outside it.
            vim.bo[qbuf].modified = false
            vim.schedule(function()
                if not api.nvim_buf_is_valid(qbuf) then
                    return
                end
                local ok, err = pcall(apply, qbuf, loclist_win)
                if not ok then
                    notify("Edit apply failed: " .. tostring(err), vim.log.levels.ERROR)
                    pcall(function()
                        vim.bo[qbuf].modified = false
                    end)
                end
            end)
        end,
    })
    api.nvim_create_autocmd("BufWipeout", {
        group = group,
        buffer = qbuf,
        callback = function()
            rows[qbuf] = nil
        end,
    })
    -- the floating PREVIEW of the entry under the cursor — follows the cursor, closes with the window
    if config.preview.enabled then
        local function show()
            local qwin = api.nvim_get_current_win()
            if not api.nvim_win_is_valid(qwin) or api.nvim_win_get_buf(qwin) ~= qbuf then
                return
            end
            preview.update(M.entry_at(qbuf, api.nvim_win_get_cursor(qwin)[1]), qwin)
        end
        api.nvim_create_autocmd("CursorMoved", { group = group, buffer = qbuf, callback = show })
        api.nvim_create_autocmd({ "WinLeave", "WinClosed", "BufWipeout" }, {
            group = group,
            buffer = qbuf,
            callback = function()
                preview.close()
            end,
        })
        vim.schedule(show) -- the first entry, on open
    end
end

--- Install the global quickfix renderer + the FileType qf hook. Idempotent.
function M.setup()
    if not config.edit.enabled then
        return
    end
    -- the renderer must be a Vimscript-callable; expose it and point the option at it
    _G.LvimQfLocTextFunc = M.textfunc
    vim.o.quickfixtextfunc = "v:lua.LvimQfLocTextFunc"
    -- the list column highlight groups (filename / lnum / separators), themed + surviving colorscheme changes
    define_highlights()
    local hlgroup = api.nvim_create_augroup("LvimQfLocEditHl", { clear = true })
    api.nvim_create_autocmd("ColorScheme", { group = hlgroup, callback = define_highlights })
    local okc, colors = pcall(require, "lvim-utils.colors")
    if okc and type(colors.on_change) == "function" then
        pcall(colors.on_change, define_highlights)
    end
    local group = api.nvim_create_augroup("LvimQfLocEditSetup", { clear = true })
    api.nvim_create_autocmd("FileType", {
        group = group,
        pattern = "qf",
        callback = function(args)
            -- AREA view: the native qf window is not the UI — swap it for the area browser. NATIVE view: wire
            -- the editable buffer + the floating preview right here.
            if config.view == "area" then
                local qwin = api.nvim_get_current_win()
                local info = vim.fn.getloclist(0, { filewinid = 0 })
                -- For a location list, hand the browser the FILE window that owns it (info.filewinid),
                -- NOT qwin: qwin is the qf window we close below, and getloclist(<closed win>) is empty —
                -- which made every area-view :lopen report "List is empty". filewinid stays valid after
                -- the qf window closes. 0 filewinid ⇒ this is a quickfix list ⇒ nil.
                local loclist_win = (info.filewinid and info.filewinid ~= 0) and info.filewinid or nil
                -- close the native qf window FIRST (force), then open the browser — so only the area UI remains
                vim.schedule(function()
                    if api.nvim_win_is_valid(qwin) then
                        pcall(api.nvim_win_close, qwin, true)
                    end
                    browser.open(loclist_win)
                end)
            else
                M.setup_buffer(args.buf)
            end
        end,
    })
end

return M
