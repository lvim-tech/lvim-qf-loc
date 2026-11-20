-- lua/lvim-qf-loc/qf/backdrop.lua
-- The NATIVE list dims the editor behind it the way the area browser does (its picker surface lays a backdrop):
-- the same look — the dock geometry's backdrop for the browser's layout, through the shared focus-aware
-- `lvim-utils.dim.apply_backdrop` — so switching views (<C-o>) does not flip the whole editor between dimmed and
-- bright. Focus-aware like every backdrop: the editor is muted while the list (or its preview / band float) has
-- the cursor, and lifts when you move into the editor. Cleared when the list window closes.
--
---@module "lvim-qf-loc.qf.backdrop"

local api = vim.api
local config = require("lvim-qf-loc.config")

local M = {}

local ID = "lvim-qf-loc-native"

--- The backdrop look the browser would get: `{ mode, amount }`, or nil (none configured, or a transparent editor).
---@return { mode: string, amount: number }?
local function look()
    local okd, dock = pcall(require, "lvim-utils.dock")
    if not (okd and type(dock.slot) == "function") then
        return nil
    end
    local ok, slot = pcall(dock.slot, config.browser.layout or "area", {})
    local bd = ok and slot and slot.backdrop
    if not bd or bd.enabled == false then
        return nil
    end
    local nb = api.nvim_get_hl(0, { name = "Normal" })
    if not (nb and nb.bg) then
        return nil -- a transparent editor: nothing to darken
    end
    local mode = bd.mode == "dim" and "dim" or "darken"
    local sub = (mode == "dim" and bd.dim or bd.darken) or {}
    return { mode = mode, amount = sub.amount or 0.5 }
end

--- The list's own windows: the list itself and every float (its preview, its band, notices) — never muted.
---@param w integer
---@return boolean
local function own(w)
    if not api.nvim_win_is_valid(w) then
        return false
    end
    return vim.bo[api.nvim_win_get_buf(w)].buftype == "quickfix" or api.nvim_win_get_config(w).relative ~= ""
end

--- Dim the editor behind the native list window `qwin` (idempotent), until that window closes.
---@param qwin integer
function M.attach(qwin)
    local okm, dim = pcall(require, "lvim-utils.dim")
    local l = look()
    if not (okm and type(dim.apply_backdrop) == "function" and l and api.nvim_win_is_valid(qwin)) then
        return
    end
    -- a real list window only (a `:colder` sets the hidden list up in Neovim's temporary "autocmd" window)
    local wt = vim.fn.win_gettype(qwin)
    if wt ~= "quickfix" and wt ~= "loclist" then
        return
    end
    dim.apply_backdrop(ID, { enabled = true, mode = l.mode, amount = l.amount, protect = own, focus_keeps = own })
    api.nvim_create_autocmd("WinClosed", {
        group = api.nvim_create_augroup("LvimQfLocBackdrop", { clear = true }),
        pattern = tostring(qwin),
        once = true,
        callback = function()
            -- another list window of this tab may still be open (a location list beside the quickfix)
            vim.schedule(function()
                for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
                    if vim.bo[api.nvim_win_get_buf(w)].buftype == "quickfix" then
                        M.attach(w)
                        return
                    end
                end
                pcall(dim.clear_backdrop, ID)
            end)
        end,
    })
end

return M
