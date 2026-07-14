-- lua/lvim-qf-loc/qf/help.lua
-- The quickfix keymap CHEATSHEET — the canonical lvim-tech help window (reference: lvim-lsp's outline
-- `show_help`): a read-only `lvim-ui.surface` float of full-width, column-aligned rows, each row a KEY
-- box + a DESCRIPTION box, striped blue (odd) / yellow (even), every box a tint of its accent (key 0.4,
-- description 0.2 — the tint canon). The hardware cursor is hidden; the row under the (hidden) cursor brightens
-- its description box to 0.4 so the whole row reads as one solid tint.
--
---@module "lvim-qf-loc.qf.help"

local api = vim.api
local config = require("lvim-qf-loc.config")

local M = {}

--- The cheatsheet rows `{ lhs, description }`, built from the live key config (only mapped keys appear).
---@return table[]
local function entries()
    local out = {}
    local function add(lhs, desc)
        if lhs and lhs ~= "" then
            out[#out + 1] = { type(lhs) == "table" and table.concat(lhs, " / ") or lhs, desc }
        end
    end
    local k = config.edit.keys or {}
    add(k.open, "open in the calling window")
    add(k.vsplit, "open in a vertical split")
    add(k.split, "open in a horizontal split")
    add(k.tab, "open in a new tab")
    local c = config.context.keys or {}
    add(c.expand, "expand context")
    add(c.collapse, "collapse context")
    add(c.toggle, "toggle context")
    add(k.help, "this help")
    add("q", "close")
    return out
end

--- Open the cheatsheet float for the quickfix keys.
function M.show()
    local ok_ui, ui = pcall(require, "lvim-ui")
    if not ok_ui then
        return
    end
    local close = { "q", "<Esc>" }
    if config.edit and config.edit.keys and config.edit.keys.help then
        close[#close + 1] = config.edit.keys.help
    end
    -- The rows / striping / colours / window are the shared component's (`lvim-ui.help`); this module only
    -- supplies the LIVE key rows.
    ui.help({ title = "QUICKFIX KEYMAPS", items = entries(), close_keys = close })
end

return M
