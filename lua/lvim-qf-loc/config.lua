-- lua/lvim-qf-loc/config.lua
-- The live configuration table. Holds the defaults; setup() merges user overrides into it IN PLACE (via the
-- shared lvim-utils.utils.merge), so every `require("lvim-qf-loc.config")` reader sees the effective values —
-- config.lua is the single source of truth. Pure data only: anything the plugin flips at runtime lives in
-- lvim-qf-loc.state, never here.
--
---@module "lvim-qf-loc.config"

---@class LvimQfLocPreviewConfig
---@field enabled     boolean            Show the floating preview of the entry under the cursor (native view).
---@field max_height  integer            Cap for the preview float's height in rows.
---@field border      string|string[]    The preview float's border — the title-canon top " " edge that carries the border-title.
---@field hl          string             Highlight group for the focused entry's line inside the preview.
---@field position    "auto"|"always"|"never"  When the title shows `line N │ col M` after the filename.
---@field scroll_down string             Key that scrolls the preview a half-page down from the list.
---@field scroll_up   string             Key that scrolls the preview a half-page up from the list.

---@class LvimQfLocEditKeys
---@field open   string  Open the entry in the window the quickfix was called from.
---@field vsplit string  Open the entry in a vertical split.
---@field split  string  Open the entry in a horizontal split.
---@field tab    string  Open the entry in a new tab.
---@field help   string  Open the keymap cheatsheet.

---@class LvimQfLocEditConfig
---@field enabled            boolean          Editable quickfix (source line is editable; `:w` writes back).
---@field autosave           "unmodified"|boolean  Which touched files to save on `:w` ("unmodified" | true | false).
---@field separator          string           Divider between the virtual `file:lnum` prefix and the editable text.
---@field max_filename_width integer          Cap for the aligned filename column (longer paths get a leading …).
---@field syntax             boolean          Treesitter-highlight each entry's source line.
---@field keys               LvimQfLocEditKeys  Keys mapped in the quickfix window.

---@class LvimQfLocContextConfig
---@field before     integer  Source lines shown BEFORE each entry when context is expanded.
---@field after      integer  Source lines shown AFTER each entry when context is expanded.
---@field dim_amount number   0..1 degree the context rows are dimmed (0 = full colour, 1 = invisible).
---@field keys       table    Context keys: `{ expand, collapse, toggle }`.

---@class LvimQfLocBrowserConfig
---@field layout       "area"|"float"|"bottom"  Where the browser opens.
---@field preview_side "above"|"below"|"right"|"left"  Where the file preview sits relative to the entry list.
---@field icons        table<string,string>     Entry `type` → its leading icon (E/W/I/N/H + `default`).

---@class LvimQfLocForce
---@field float  table  Per-open ANCHORED geometry override for the FLOAT layout (height/height_auto/width/width_auto/backdrop/auto_hide/keep_focus); `{}` = inherit the global.
---@field area   table  Per-open ANCHORED geometry override for the AREA layout (always full-width — no width/width_auto); `{}` = inherit the global.
---@field bottom table  Per-open ANCHORED geometry override for the BOTTOM layout (always full-width — no width/width_auto); `{}` = inherit the global.

---@class LvimQfLocDock
---@field dock_stack boolean         Route the area BROWSER through the managed dock STACK (cyclable, one-visible-per-layout) vs. a standalone open.
---@field force      LvimQfLocForce  Per-layout ANCHORED geometry overrides for the browser, deep-merged over the global `lvim-utils.config.dock.geometry`.

---@class LvimQfLocConfig
---@field notify       boolean                 Emit notifications (vim.notify) for list navigation / errors.
---@field dock         LvimQfLocDock           Dock routing for the area BROWSER: managed-stack membership + per-layout geometry overrides.
---@field min_height   integer                 Minimum quickfix window height (rows).
---@field max_height   integer                 Maximum quickfix window height (rows).
---@field cfilter      boolean                 `packadd` Neovim's built-in `cfilter` on setup (`:Cfilter`/`:Lfilter`).
---@field view         "native"|"area"         Which UI the quickfix opens in.
---@field preview      LvimQfLocPreviewConfig  The floating preview of the entry under the cursor (native view).
---@field edit         LvimQfLocEditConfig     The editable quickfix (source line editable; `:w` writes back).
---@field context      LvimQfLocContextConfig  Context expand/collapse (source lines around each entry).
---@field browser      LvimQfLocBrowserConfig  The quickfix / location browser in the lvim-utils area.
---@field tabs         table<string,table>     Management-popup tab icons (`browse`/`delete`/`storage`).
---@field popup_global table                   Options passed to the lvim-utils UI instance (keys/icons/labels — NOT size; the surface derives its slot from the central lvim-utils geometry).

---@type LvimQfLocConfig
return {
    notify = true,
    min_height = 1,
    max_height = 15,

    -- DOCK routing for the area BROWSER (qf/browser.lua, opened through the lvim-picker). Applies ONLY to that
    -- picker-based browser — the native quickfix window and the cursor-preview float are content-fit and are NOT
    -- dock consumers, so this never touches them.
    dock = {
        -- DOCK STACK membership:
        --   true  — full dock-STACK consumer: managed by lvim-utils.dock (cyclable <Leader>n/p/x/m, :LvimDock,
        --           one-visible-per-layout, no overlap; parks any other visible consumer in the same layout).
        --   false — geometry-only: still sized centrally (dock.slot + `force` below), but opens STANDALONE, not
        --           in the stack.
        dock_stack = true,

        -- Per-layout ANCHORED geometry overrides for the browser, deep-merged PER FIELD over the global
        -- `lvim-utils.config.dock.geometry.<layout>`; an empty `{}` inherits the global unchanged. Each layout
        -- may carry: `height`, `height_auto`, `backdrop = { enabled, mode, dim = { amount }, darken = { amount }
        -- }`, `auto_hide`, `keep_focus`. FLOAT may ALSO carry `width` / `width_auto`; `area` and `bottom` are
        -- ALWAYS full-width, so any width/width_auto set on them is ignored. Forwarded to `picker.open` as
        -- `force`, which feeds `force[layout]` to `dock.slot` as the per-open override.
        force = { float = {}, area = {}, bottom = {} },
    },

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
        -- The title-canon border: a top " " edge ONLY (no ring), which CARRIES the centered `file │ line │ col`
        -- native border-title — the borderless `config.ui.border = "none"` has no top edge, so a titled float
        -- needs its own. Resolved (corners filled) by lvim-ui.util; matches the help-window canon.
        border = { "", " ", "", "", "", "", "", "" },
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
        -- No `height` here on purpose: the browser opens through the lvim-picker (a 3-layout float/area/bottom
        -- dock consumer), and the SLOT geometry of those layouts is owned centrally by lvim-utils
        -- (`config.dock.geometry`, surfaced by the picker's own `preview_heights`). The browser passes NO size,
        -- so the surface derives it from the single authority — every dock consumer lands in the identical rect.
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
        position = "editor",
        -- No size here (width/height/max_*): the management popup opens with `lvim-ui.tabs`, whose slot geometry
        -- comes from the central lvim-utils float size (`lvim-ui.size("float")` → `config.dock.geometry.float`).
        -- `lvim-ui.new` explicitly ignores size from the instance defaults, so passing it here is a duplicate.
        max_items = nil, -- content-fit list cap (NOT a slot size) — kept; nil = no cap
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
