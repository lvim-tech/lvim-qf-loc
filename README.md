# LVIM QF AND LOC

## Improvements for neovim quickfix and location

- Navigation (prev / next) via floating popup
- Switch between quickfix / location lists
- Delete quickfix / location lists
- Save and load lists to/from JSON file
- Diagnostics in quickfix
- Floating tabbed UI powered by [lvim-utils](https://github.com/lvim-tech/lvim-utils) (optional, falls back gracefully)

![lvim-logo](https://user-images.githubusercontent.com/82431193/115121988-3bc06800-9fbe-11eb-8dab-19f624aa7b93.png)

[![License](https://img.shields.io/badge/License-BSD%203--Clause-blue.svg)](https://github.com/lvim-tech/lvim-colorscheme/blob/main/LICENSE)

## Requirements

- Neovim 0.9+
- [lvim-utils](https://github.com/lvim-tech/lvim-utils) _(optional — enables the floating tabbed UI)_

## Installation

### 1. [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
    "lvim-tech/lvim-qf-loc",
    dependencies = {
        "lvim-tech/lvim-utils",
    },
    config = function()
        require("lvim-qf-loc").setup({ ... })
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

## Default configuration

```lua
require("lvim-qf-loc").setup({
    notify = true,
    min_height = 1,
    max_height = 15,

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
