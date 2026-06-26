# LVIM QF AND LOC

Improvements for Neovim's quickfix and location lists — a floating, tabbed UI to
navigate, switch, delete and persist lists, plus a full quickfix workflow: a live
**preview**, an **editable** quickfix that writes back to your files, **context**
expand/collapse, project-wide **search & replace**, a **history** picker, and a **browser**
in the lvim-utils area. A self-contained replacement for nvim-bqf + quicker.nvim — crash-safe
by design (no FFI, no "magicwin" scroll math, no delimiter parsing).
Powered by [lvim-utils](https://github.com/lvim-tech/lvim-utils) (optional, falls back
gracefully).

[![License: BSD-3-Clause](https://img.shields.io/badge/License-BSD--3--Clause-blue.svg)](https://github.com/lvim-tech/lvim-qf-loc/blob/main/LICENSE)

![lvim-logo](https://user-images.githubusercontent.com/82431193/115121988-3bc06800-9fbe-11eb-8dab-19f624aa7b93.png)

## Features

- Navigation (prev / next) via floating popup
- Switch between quickfix / location lists
- Delete quickfix / location lists
- Save and load lists to/from JSON file
- Diagnostics in quickfix
- Floating tabbed UI powered by [lvim-utils](https://github.com/lvim-tech/lvim-utils) (optional, falls back gracefully)

**Quickfix module** (replaces nvim-bqf + quicker.nvim):

- **Preview** — a live float of the entry under the cursor (real file buffer, syntax-highlighted), no FFI / magicwin
- **Editable** — each entry's source line is editable; `:w` writes the changes back to the files, crash-safe
  (writes only when the file still matches; conflict detection; every op guarded)
- **Context** — expand / collapse N source lines around each entry (`>` / `<`)
- **Search & replace** — one Vim-regex substitution across every entry's source line (`:LvimQfReplace`)
- **History picker** — jump to any past quickfix / location list (`:LvimQfHistory`)
- **Browser** — the list + a real-Neovim preview in the lvim-utils area, with fuzzy narrowing, marking and a
  severity filter bar (`:LvimQfBrowse`)
- **One UI, your choice** — `config.view` (`"native"` or `"area"`) picks which UI the quickfix uses

## Requirements

- Neovim 0.9+ (0.10+ recommended for the editable quickfix + preview)
- [lvim-utils](https://github.com/lvim-tech/lvim-utils) _(optional — enables the tabbed UI, the area view, the browser and the history picker)_

> Disable **nvim-bqf** and **quicker.nvim** if you use them — this plugin owns `quickfixtextfunc` and the
> quickfix window, and the three would conflict. Run `:checkhealth lvim-qf-loc` to verify.

## Installation

### 1. [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
return {
    "lvim-tech/lvim-qf-loc",
    dependencies = {
        "lvim-tech/lvim-utils",
    },
    config = function()
        require("lvim-qf-loc").setup({})
    end,
}
```

### Native (vim.pack / packadd)

```lua
vim.pack.add({
    { src = "https://github.com/lvim-tech/lvim-utils" },
    { src = "https://github.com/lvim-tech/lvim-qf-loc" },
})

require("lvim-qf-loc").setup({ ... })
```

### 3. [Packer](https://github.com/wbthomason/packer.nvim)

```lua
use({
    "lvim-tech/lvim-qf-loc",
    requires = {
        { "lvim-tech/lvim-utils" },
    },
    config = function()
        require("lvim-qf-loc").setup({ ... })
    end,
})
```

## Commands

Two commands with tab-completion for subcommands:

### `:LvimQf [subcommand]`

| Subcommand    | Description                         |
| ------------- | ----------------------------------- |
| `navigate`    | Open / Close / Next / Previous      |
| `switch`      | Switch to a different quickfix list |
| `delete`      | Delete a quickfix list              |
| `storage`     | Save / Load lists to/from JSON      |
| `diagnostics` | Load diagnostics into quickfix      |

### `:LvimLoc [subcommand]`

| Subcommand | Description                         |
| ---------- | ----------------------------------- |
| `navigate` | Open / Close / Next / Previous      |
| `switch`   | Switch to a different location list |
| `delete`   | Delete a location list              |
| `storage`  | Save / Load lists to/from JSON      |

Running the command **without a subcommand** opens the popup on the first tab.
Running it **with a subcommand** opens the popup with that tab active.

### Quickfix module commands

| Command          | Description                                                       |
| ---------------- | ---------------------------------------------------------------- |
| `:LvimQfBrowse`  | Browse the quickfix list in the area (preview, fuzzy, mark)       |
| `:LvimLocBrowse` | Browse the current window's location list                        |
| `:LvimQfReplace` | Project-wide search & replace across the quickfix entries        |
| `:LvimLocReplace`| Search & replace across the location list                        |
| `:LvimQfHistory` | Pick from the quickfix history                                    |
| `:LvimLocHistory`| Pick from the location-list history                              |

### The two views

`config.view` picks the single UI the quickfix opens in — so `:copen` and the list always look the same:

- **`"native"`** (default) — the native quickfix window: each entry's **source line is editable** (`:w` writes
  the files), **context** expand/collapse with `>` / `<`, and a floating **preview** of the entry under the
  cursor.
- **`"area"`** — `:copen` opens the **browser** in the lvim-utils area instead (list + preview, fuzzy, marking,
  `<C-q>` → a new list, severity filter bar). `:LvimQfBrowse` opens it explicitly in either view.

In the **native** view's editable window: edit any source line and `:w` to apply; `>` / `<` to grow / shrink
context. An edit is written only when the file still matches what was shown (external changes are skipped, not
clobbered).

## Default configuration

```lua
require("lvim-qf-loc").setup({
    notify = true,
    min_height = 1,
    max_height = 15,

    -- Which UI the quickfix opens in: "native" (editable window + floating preview + context)
    -- or "area" (the lvim-utils area browser). :LvimQfBrowse always opens the area explicitly.
    view = "native",

    -- (native view) the floating preview of the entry under the cursor
    preview = {
        enabled = true,
        max_height = 15,
        border = "rounded",
        hl = "Visual", -- the focused line's highlight in the preview
    },

    -- the editable quickfix: :w writes each entry's edited source line back to its file
    edit = {
        enabled = true,
        autosave = "unmodified", -- "unmodified" | true | false
        separator = "│",
    },

    -- context expand/collapse (keys are mapped in the quickfix window)
    context = {
        before = 3,
        after = 3,
        keys = { expand = ">", collapse = "<", toggle = "" },
    },

    -- the area browser
    browser = {
        layout = "area",
        icons = { E = "󰅚 ", W = "󰀪 ", I = " ", N = " ", H = " ", default = " " },
    },

    -- Icons shown on each popup tab (requires a Nerd Font)
    tabs = {
        navigate = { icon = "󰜌" },
        switch = { icon = "󰒊" },
        delete = { icon = "󰆴" },
        storage = { icon = "󰆼" },
        diagnostics = { icon = "󰋽" },
    },

    -- Passed directly to lvim-utils ui.new() — overrides border, size, keys, icons, highlights, etc.
    popup_global = {
        border = { "", "", "", " ", " ", " ", " ", " " },
        position = "editor",
        width = 0.8,
        height = 0.8,

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
