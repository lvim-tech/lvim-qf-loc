return {
    notify = true,
    min_height = 1,
    max_height = 15,

    -- Load Neovim's built-in `cfilter` plugin on setup, so `:Cfilter` / `:Lfilter` (filter the quickfix /
    -- location list to entries matching, or with `!` not matching, a pattern) are available — they pair
    -- naturally with this quickfix UI. It ships with Neovim but is an OPT plugin (not auto-loaded). Off = leave
    -- it to the user's own `packadd cfilter`.
    cfilter = true,

    -- WHICH quickfix UI is the active one (so `:copen` and the list always open the SAME way — no two
    -- competing UIs). Both are fully featured; pick the one you like and switch any time:
    --   "native" — the native quickfix window: each entry's source line is EDITABLE (`:w` writes the files),
    --              context expand/collapse, and a floating PREVIEW of the entry under the cursor.
    --   "area"   — the lvim-utils AREA: the list + a real-Neovim preview, with fuzzy narrowing, the mark dot,
    --              `<C-q>` → a new list, and the severity filter bar.
    -- `:LvimQf browse` always opens the area view explicitly, regardless of this.
    view = "native",

    -- (native view) The floating PREVIEW of the entry under the cursor (qf/preview.lua).
    preview = {
        enabled = true,
        max_height = 15,
        border = "rounded",
        hl = "Visual", -- the focused entry's line highlight inside the preview
        -- whether the title shows `line N │ col M` after the filename:
        --   "auto"   — only for non-diagnostic lists (grep / references), where the position is a match
        --   "always" / "never"
        position = "auto",
        -- scroll the preview a half-page from the LIST (peek more context) without leaving it
        scroll_down = "<C-d>",
        scroll_up = "<C-u>",
    },

    -- The EDITABLE quickfix (qf/edit.lua): the native qf buffer shows each entry's SOURCE LINE (editable);
    -- saving the buffer applies the edits to the files. `autosave` = "unmodified" (save files that were not
    -- already dirty) | true (always) | false (never). `separator` divides the virtual `file:lnum` prefix from
    -- the editable text. Set `enabled = false` to keep the native read-only quickfix.
    edit = {
        enabled = true,
        autosave = "unmodified",
        separator = "│",
        max_filename_width = 40, -- cap for the aligned filename column (longer paths get a leading …)
        syntax = true, -- treesitter-highlight each entry's source line (like quicker)
        -- keys in the quickfix window: open the entry in the window the qf was called from, or in a split / tab
        keys = {
            open = "<CR>",
            vsplit = "<C-v>",
            split = "<C-x>",
            tab = "<C-t>",
            help = "g?", -- the keymap cheatsheet
        },
    },

    -- CONTEXT expand/collapse (qf/context.lua): show N source lines around each entry. Keys are mapped in the
    -- quickfix window; expanding accumulates (press again for more).
    context = {
        before = 3,
        after = 3,
        -- How strongly the context rows are DIMMED — a 0..1 degree of dimming: 0 = no dim (full syntax colour),
        -- 1 = fully merged into the background (invisible). Higher = dimmer, lower = more readable.
        dim_amount = 0.4,
        keys = { expand = "zo", collapse = "zc", toggle = "" },
    },

    -- The quickfix / location BROWSER (qf/browser.lua): the list + a real-Neovim preview in the lvim-utils
    -- area, with a severity icon per entry. `layout` = "area" | "float" | "bottom".
    browser = {
        layout = "area",
        -- Where the editable file PREVIEW sits relative to the entry list: "above" (default — preview on top,
        -- the list spans the FULL width below so long paths + messages stay readable) | "below" | "right" |
        -- "left". The preview is the real file buffer (editable); enter it with the panel-nav keys to edit.
        -- `<C-n>` / `<C-p>` rotate it through the four sides live.
        preview_side = "above",
        -- The area's height for each stack direction: `horizontal` when the preview is left/right (side-by-side),
        -- `vertical` when it is above/below (stacked — usually taller, so both panels get room). A value ≤ 1 is a
        -- fraction of the screen height; > 1 an absolute row count.
        height = {
            horizontal = 0.33,
            vertical = 0.66,
        },
        -- entry `type` → its leading icon (E/W/I/N/H from diagnostic-sourced lists; `default` for plain rows).
        icons = {
            E = "󰅚 ",
            W = "󰀪 ",
            I = " ",
            N = " ",
            H = " ",
            default = " ",
        },
    },

    tabs = {
        browse = { icon = "󰒊" },
        delete = { icon = "󰆴" },
        storage = { icon = "󰆼" },
    },

    popup_global = {
        border = { "", "", "", " ", " ", " ", " ", " " },
        position = "editor",
        width = 0.9, -- fraction of the screen wide for the management popup
        max_width = 0.8,
        height = 0.8,
        max_height = 0.8,
        max_items = nil,
        close_keys = { "q", "<Esc>" },
        markview = false,

        icons = {
            bool_on = "󰄬",
            bool_off = "󰍴",
            select = "󰘮",
            number = "󰎠",
            string = "󰬴",
            action = "",
            spacer = "   ──────",
            multi_selected = "󰄬",
            multi_empty = "󰍴",
            current = "➤",
        },

        labels = {
            navigate = "navigate",
            confirm = "confirm",
            cancel = "cancel",
            close = "close",
            toggle = "toggle",
            cycle = "cycle",
            edit = "edit",
            execute = "execute",
            tabs = "tabs",
        },

        keys = {
            down = "j",
            up = "k",
            confirm = "<CR>",
            cancel = "<Esc>",
            close = "q",

            tabs = {
                next = "l",
                prev = "h",
            },

            select = {
                confirm = "<CR>",
                cancel = "<Esc>",
            },

            multiselect = {
                toggle = "<Space>",
                confirm = "<CR>",
                cancel = "<Esc>",
            },

            list = {
                next_option = "<Tab>",
                prev_option = "<BS>",
            },

            back = "u",
        },

        highlights = {},
    },
}
