# LVIM QF AND LOC

## Improvements for neovim quickfix and location

-   navigation (prev / next)
-   menu choice quickfix lists
-   menu delete quickfix list
-   menu choice loc lists
-   menu delete loc lists
-   save quickfix lists in json file
-   load quickfix lists from json file
-   save loc lists in json file
-   load loc lists from json file

![lvim-logo](https://user-images.githubusercontent.com/82431193/115121988-3bc06800-9fbe-11eb-8dab-19f624aa7b93.png)

[![License](https://img.shields.io/badge/License-BSD%203--Clause-blue.svg)](https://github.com/lvim-tech/lvim-colorscheme/blob/main/LICENSE)

## Screenshots

![1](https://github.com/lvim-tech/lvim-qf-loc/assets/82431193/1f4fd211-9651-45ce-ad4a-783c795d1554)
![2](https://github.com/lvim-tech/lvim-qf-loc/assets/82431193/233395cb-6504-45a3-9a17-27348ed7cce3)
![3](https://github.com/lvim-tech/lvim-qf-loc/assets/82431193/363d7811-25fb-407e-8544-2b02a2b45857)

## Requirements

-   [MunifTanjim/nui.nvim](https://github.com/MunifTanjim/nui.nvim)
-   [rcarriga/nvim-notify](https://github.com/rcarriga/nvim-notify)
-   [lvim-tech/lvim-ui-config](https://github.com/lvim-tech/lvim-ui-config)

## Installation

Install the plugin with your preferred package manager:

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
require("lazy").setup({
  {
    "lvim-tech/lvim-qf-loc",
    dependencies = {
      "MunifTanjim/nui.nvim",
      "rcarriga/nvim-notify",
      "lvim-tech/lvim-ui-config",
    },
    config = function()
      require("lvim-qf-loc").setup({
        -- your configuration comes here
        -- or leave it empty to use the default settings
        -- refer to the configuration section below
      })
    end,
  },
})
```

### [packer](https://github.com/wbthomason/packer.nvim)

```lua
use({
  "lvim-tech/lvim-qf-loc",
  requires = {
    "MunifTanjim/nui.nvim",
    "rcarriga/nvim-notify",
    "lvim-tech/lvim-ui-config",
  },
  config = function()
    require("lvim-qf-loc").setup({
      -- your configuration comes here
      -- or leave it empty to use the default settings
      -- refer to the configuration section below
    })
  end,
})
```

## Default configuration

```lua
{
  notify = true,
}
```

## Commans

```lua
:LvimListQuickFixNext
:LvimListQuickFixPrev
:LvimListLocNext
:LvimListLocPrev
:LvimListQuickFixMenuChoice
:LvimListLocMenuChoice
:LvimListQuickFixMenuDelete
:LvimListQuickFixSave
:LvimListQuickFixLoad
:LvimListLocSave
:LvimListLocLoad
```
