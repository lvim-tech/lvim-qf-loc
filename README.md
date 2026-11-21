# LVIM QF AND LOC

Improvements for Neovim's quickfix and location lists — a tabbed UI to browse, delete
and persist lists, plus a full quickfix workflow: a live **preview**, an **editable**
quickfix that writes back to your files, **context** expand/collapse, and a **browser**
in the lvim-utils area. Self-contained and crash-safe by design: no FFI, no scroll
math against the window's internal state, no delimiter parsing of the rendered line.
Powered by [lvim-ui](https://github.com/lvim-tech/lvim-ui) and
[lvim-picker](https://github.com/lvim-tech/lvim-fuzzy-picker) (optional, falls back gracefully).

[![License: BSD-3-Clause](https://img.shields.io/badge/License-BSD--3--Clause-blue.svg)](https://github.com/lvim-tech/lvim-qf-loc/blob/main/LICENSE)

![lvim-logo](https://user-images.githubusercontent.com/82431193/115121988-3bc06800-9fbe-11eb-8dab-19f624aa7b93.png)

## Features

- Navigate the list directly — `:LvimQf open` / `close` / `next` / `prev`
- Browse, delete and persist lists from a tabbed popup
- Save and load lists to/from a per-project JSON file
- Load diagnostics into the quickfix and browse them
- Tabbed UI powered by [lvim-ui](https://github.com/lvim-tech/lvim-ui) (optional, falls back gracefully)

**Quickfix module**:

- **Preview** — a live float of the entry under the cursor (real file buffer, syntax-highlighted), no FFI / magicwin;
  `<C-d>` / `<C-u>` scroll it from the list (peek more context). The search the list came from is marked in it
  and in the list rows — every match, the entry's own one harder: a grep sent from lvim-picker (`<C-q>`) keeps
  its pattern in the list, and a `:vimgrep` names it in its title
- **Editable** — each entry's source line is editable; `:w` writes the changes back to the files, crash-safe
  (writes only when the file still matches; conflict detection; every op guarded). A plain **file list** instead
  edits each row's **path** — `:w` renames / moves the file (creates parent dirs, never overwrites)
- **Context** — expand / collapse N source lines around each entry (`zo` / `zc`)
- **Browser** — the list + a real-Neovim preview in the lvim-utils area, with fuzzy narrowing, marking and a
  severity filter bar (`:LvimQf area` / `float` / `bottom`); its rows are the editable quickfix's own — the
  ordinal, the aligned file and `lnum, col` columns and the treesitter-coloured source line, with a grep match
  marked. The **Browse** tab of `:LvimQf` lists every stored list, pick one to browse it
- **In-window open keys** — in the editable quickfix, `<CR>` opens the entry in the calling window, `<C-v>` in a
  vertical split, `<C-x>` in a horizontal split, `<C-t>` in a new tab; `g?` shows the keymap cheatsheet
- **A button band you can step into** — the bar above the list is a real sector, not a legend: `<C-k>` from the
  list (or `<C-j>` from the window above) focuses it, `h` / `l` pick a button, `<CR>` runs it, `<C-j>` / `q`
  return to the list. It sits on the window's winbar row, so it costs the list no line
- **`:Cfilter` / `:Lfilter`** — Neovim's built-in list filter is `packadd`ed on setup (`config.cfilter`), a
  natural companion for narrowing the quickfix / location list
- **`]q` / `[q`, `]l` / `[l` done right** — the file opens in an editor window (never in the browser's
  preview float, even with `switchbuf=useopen`), the first press goes to the current entry instead of skipping
  it, the list wraps around at its ends (`jump.wrap`), and an open browser's selection follows
- **Lists from the list** — `<C-n>` / `<C-p>` (`config.step`) in either view show the newer / older list of the
  history right there (in the browser they take over the preview-side rotation)
- **Switch views live** — `<C-o>` (`config.switch`) in either view, or `:LvimQf switch`, shows the same list in
  the other one (native ⇄ area); the choice holds for the session
- **Edit in the browser too** — `e` (`browser.edit_key`) on the browser's list makes its rows editable in place,
  as the native window always is: each row becomes its entry's source line (a file list: its path), `:w` writes
  the changed lines to their files (renames / moves the files), the preview follows the row being edited, and
  `<Esc>` / `q` go back to the list (asking first about unwritten edits)
- **One UI, your choice** — `config.view` (`"native"` or `"area"`) picks which UI the quickfix uses

## Requirements

- Neovim 0.12+
- [lvim-ui](https://github.com/lvim-tech/lvim-ui) _(optional — enables the tabbed management popup)_
- [lvim-picker](https://github.com/lvim-tech/lvim-fuzzy-picker) _(optional — enables the area view and the browser)_

> This plugin owns `quickfixtextfunc` and the quickfix window, so any other plugin that also
> claims them will conflict — keep only one. Run `:checkhealth lvim-qf-loc` to verify.

## Installation

Requires Neovim >= 0.12.

### lvim-installer (recommended)

Install and manage it from the LVIM package manager — open the **Plugins** tab and install / update / pin it:

```vim
:LvimInstaller plugins
```

lvim-installer installs plugins through Neovim's built-in `vim.pack`, so no external plugin manager is needed.

### Native (vim.pack)

```lua
vim.pack.add({
    { src = "https://github.com/lvim-tech/lvim-ui" },
    { src = "https://github.com/lvim-tech/lvim-fuzzy-picker" },
    { src = "https://github.com/lvim-tech/lvim-qf-loc" },
})
require("lvim-qf-loc").setup({})
```

## Commands

Two commands with tab-completion for subcommands:

### `:LvimQf [subcommand]`

| Subcommand    | Description                                                                      |
| ------------- | ------------------------------------------------------------------------------- |
| *(none)*      | open the management popup on the **Browse** tab                                  |
| `open`        | open the current quickfix window (`:copen`)                                      |
| `close`       | close it (`:cclose`)                                                             |
| `next`        | jump to the next entry (`:cnext`)                                                |
| `prev`        | jump to the previous entry (`:cprev`)                                            |
| `diagnostics` | load the diagnostics into a list + open the browser (or notify when none)       |
| `browse`      | popup on the **Browse** tab — every stored list; pick one → browse its entries  |
| `delete`      | popup on the **Delete** tab — remove a stored list                              |
| `storage`     | popup on the **Storage** tab — save / load all lists to a per-project JSON      |
| `area` · `float` · `bottom` | open the **browser** on the current list in that layout (also remembered for the session) |
| `switch`      | show the current list in the other view (native ⇄ area); the view stays for the session |

### `:LvimLoc [subcommand]`

The same set **without `diagnostics`** (location lists carry no diagnostics); every subcommand acts on the
window that was current when the command ran (`open`/`close`/`next`/`prev` → `:lopen`/`:lclose`/`:lnext`/`:lprev`).

Running either command **without a subcommand** opens the popup on its first tab (**Browse**); **with** a
subcommand it either runs the action directly (`open`/`close`/`next`/`prev`/`diagnostics`) or opens the popup on
that tab (`browse`/`delete`/`storage`). A layout word **alone** (`:LvimQf area`) opens the browser on the current
list in that layout; next to a subcommand it only picks the layout that subcommand's browser uses
(`:LvimQf diagnostics bottom`).

### The two views

`config.view` picks the single UI the quickfix opens in — so `:copen` and the list always look the same:

- **`"native"`** (default) — the native quickfix window: each entry's **source line is editable** (`:w` writes
  the files), **context** expand/collapse with `zo` / `zc`, and a floating **preview** of the entry under the
  cursor.
- **`"area"`** — `:copen` opens the **browser** in the lvim-utils area instead (list + preview, fuzzy, marking,
  `<C-q>` → a new list, severity filter bar). `:LvimQf area` (or `float` / `bottom`) opens it explicitly in
  either view.

In the **native** view's editable window: edit any source line and `:w` to apply; `zo` / `zc` to grow / shrink
context; `<CR>` / `<C-v>` / `<C-x>` / `<C-t>` open the entry in the calling window / a vertical split / a
horizontal split / a new tab; `g?` shows the keymap cheatsheet. An edit is written only when the file still
matches what was shown (external changes are skipped, not clobbered).

## Default configuration

```lua
require("lvim-qf-loc").setup({
    notify = true,

    -- Border-title alignment for the browser and the LvimQf/LvimLoc management popup —
    -- layout-independent (float / area / bottom all the same). The title text itself stays
    -- dynamic per list kind ("Quickfix" / "Location List").
    title_pos = "center", -- "left" | "center" | "right"

    min_height = 1,
    max_height = 15, -- only without lvim-utils: else the native window shows as many entries as the area browser

    -- Dock routing for the area BROWSER only (the native quickfix window and the
    -- cursor-preview float are content-fit and never dock consumers):
    dock = {
        -- Dock STACK membership:
        --   true  — managed dock-STACK consumer (cyclable <Leader>n/p/x/m, :LvimDock,
        --           one-visible-per-layout, no overlap)
        --   false — geometry-only: still centrally sized, but opens standalone (not in the stack)
        dock_stack = true,

        -- Per-layout ANCHORED geometry overrides for the browser, deep-merged per field over the
        -- global lvim-utils dock geometry; empty {} inherits it. Each layout may carry height,
        -- height_auto, backdrop = { enabled, mode, dim = { amount }, darken = { amount } },
        -- auto_hide, keep_focus. float may ALSO carry width / width_auto; area and bottom are
        -- always full-width.
        force = { float = {}, area = {}, bottom = {} },
    },

    -- packadd Neovim's built-in cfilter on setup, so :Cfilter / :Lfilter are available
    cfilter = true,

    -- Which UI the quickfix opens in: "native" (editable window + floating preview + context)
    -- or "area" (the lvim-utils area browser). :LvimQf area|float|bottom opens the browser in either view.
    view = "native",
    switch = "<C-o>", -- switch the list between the two views, live, in both (also :LvimQf switch); "" = none
    -- in the list (both views): the newer / older list of the history
    step = { next = "<C-n>", prev = "<C-p>" },

    -- ]q / [q and ]l / [l (replacing Neovim's own): open in an editor window, start at the current entry,
    -- wrap around at the ends, move an open browser's selection along
    jump = {
        enabled = true,
        wrap = true,
        keys = { qf_next = "]q", qf_prev = "[q", loc_next = "]l", loc_prev = "[l" },
    },

    -- (native view) the floating preview of the entry under the cursor
    preview = {
        enabled = true,
        max_height = 15, -- only without lvim-utils: else the browser's peek cap (the area's dynamic preview height)
        -- the title-canon border: a top " " edge only (no ring) that carries the border-title
        border = { "", " ", "", "", "", "", "", "" },
        hl = "Visual", -- the focused line's highlight in the preview
        position = "auto", -- show `line N │ col M` in the title: "auto" | "always" | "never"
        scroll_down = "<C-d>", -- scroll the preview a half-page from the list
        scroll_up = "<C-u>",
    },

    -- the editable quickfix: :w writes each entry's edited source line back to its file
    edit = {
        enabled = true,
        autosave = "unmodified", -- "unmodified" | true | false
        separator = "│",
        max_filename_width = 40, -- cap for the aligned filename column
        syntax = true, -- treesitter-highlight each entry's source line
        keys = {
            open = "<CR>", -- open in the window the quickfix was called from
            vsplit = "<C-v>",
            split = "<C-x>",
            tab = "<C-t>",
            help = "g?", -- the keymap cheatsheet
        },
    },

    -- context expand/collapse (keys are mapped in the quickfix window)
    context = {
        before = 3,
        after = 3,
        dim_amount = 0.4, -- 0..1: how strongly context rows are dimmed (0 = none, 1 = invisible)
        keys = { expand = "zo", collapse = "zc", toggle = "" },
    },

    -- the area browser (its slot height comes from the central lvim-utils dock geometry — no size here)
    browser = {
        layout = "area", -- "area" | "float" | "bottom"
        preview_side = nil, -- nil = lvim-picker's preview_side; or "right" | "left" | "dynamic" (rotate live with <C-n>/<C-p>)
        edit_key = "e", -- on the list: edit its rows in place (:w writes, <Esc> / q back); "" = none
        icons = { E = "󰅚 ", W = "󰀪 ", I = " ", N = " ", H = " ", default = " " },
    },

    -- Icons shown on each popup tab (requires a Nerd Font)
    tabs = {
        browse = { icon = "󰒊" },
        delete = { icon = "󰆴" },
        storage = { icon = "󰆼" },
    },

    -- Passed directly to lvim-utils ui.new() — overrides keys, icons, highlights, etc. (NOT size: the
    -- management popup sizes from the central lvim-utils float geometry. The frame border follows the
    -- single shared lvim-utils `config.ui.border`.)
    popup_global = {
        position = "editor",

        icons = {
            action = "",
            -- ...
        },

        keys = {
            down = "j",
            up = "k",
            confirm = "<CR>",
            cancel = "<Esc>",
            close = "q",
            tabs = { next = "l", prev = "h" },
        },

        highlights = {},
    },
})
```
