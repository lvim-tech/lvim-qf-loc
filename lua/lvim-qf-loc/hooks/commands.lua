-- lua/lvim-qf-loc/hooks/commands.lua
-- The two unified commands `:LvimQf` / `:LvimLoc <subcommand>`:
--   open · close · next · prev   → drive the list directly (no popup)
--   diagnostics  (quickfix only) → load the diagnostics into a list + open the browser, or notify when none
--   browse · delete · storage    → open the management popup on that tab
--   area · float · bottom        → open the browser on the current list in that layout
--   switch                       → the other view (native ⇄ area) on the current list
-- No argument opens the popup on its first tab (Browse). For LvimLoc a subcommand acts on the window that was
-- current when the command ran.
--
---@module "lvim-qf-loc.hooks.commands"

local popup = require("lvim-qf-loc.ui.popup")
local nav = require("lvim-qf-loc.core.nav")
local diagnostics = require("lvim-qf-loc.core.diagnostics")
local config = require("lvim-qf-loc.config")

local M = {}

--- The subcommand → handler table for one kind ("quick_fix" | "loc").
---@param kind "quick_fix"|"loc"
---@return table<string, function>
local function actions(kind)
    local is_qf = kind == "quick_fix"
    -- A loc subcommand acts on the window current WHEN the command runs (captured at call time, not setup).
    local function win()
        -- (not `is_qf and nil or …`: `x and nil or y` is always y in Lua)
        if is_qf then
            return nil
        end
        return vim.api.nvim_get_current_win()
    end
    local a = {
        open = is_qf and nav.quick_fix_open or nav.loc_list_open,
        close = is_qf and nav.quick_fix_close or nav.loc_list_close,
        next = is_qf and nav.quick_fix_next or nav.loc_list_next,
        prev = is_qf and nav.quick_fix_prev or nav.loc_list_prev,
        browse = function()
            popup.open(kind, "browse", win())
        end,
        delete = function()
            popup.open(kind, "delete", win())
        end,
        storage = function()
            popup.open(kind, "storage", win())
        end,
        -- the other view (native ⇄ area) on the current list
        switch = function()
            require("lvim-qf-loc.qf.view").switch(win())
        end,
    }
    if is_qf then
        a.diagnostics = diagnostics.qf_diagnostics -- quickfix only — location lists carry no diagnostics
    end
    return a
end

---@param name string  the command name
---@param kind "quick_fix"|"loc"
local function register(name, kind)
    local a = actions(kind)
    local keys = vim.tbl_keys(a)
    table.sort(keys)
    vim.api.nvim_create_user_command(name, function(opts)
        -- A layout token (area|float|bottom) anywhere overrides `config.browser.layout` for this open — sticky
        -- for the session (config is the live authority a command may override); the remaining word is the
        -- subcommand. A layout alone opens the browser on the current list (`:LvimQf area`); with a subcommand it only
        -- sets the layout that subcommand's browser uses (`:LvimQf diagnostics bottom`); nothing → the Browse popup.
        local LAYOUTS = { area = true, float = true, bottom = true }
        local sub, layout
        for _, w in ipairs(opts.fargs) do
            if LAYOUTS[w] then
                config.browser.layout = w
                layout = w
            elseif not sub then
                sub = w
            end
        end
        if not sub and layout then -- only a layout → the browser on the current list, in that layout
            require("lvim-qf-loc.qf.browser").open(kind == "loc" and vim.api.nvim_get_current_win() or nil, layout)
            return
        end
        if not sub then -- no subcommand → the popup on its first tab (Browse)
            popup.open(kind, nil, kind == "loc" and vim.api.nvim_get_current_win() or nil)
            return
        end
        local fn = a[sub]
        if not fn then
            vim.notify(name .. ": unknown subcommand '" .. sub .. "'", vim.log.levels.WARN, { title = "LVIM LIST" })
            return
        end
        fn()
    end, {
        nargs = "*",
        complete = function(arglead)
            local pool = vim.list_extend(vim.deepcopy(keys), { "area", "float", "bottom" })
            return vim.tbl_filter(function(k)
                return vim.startswith(k, arglead)
            end, pool)
        end,
    })
end

M.setup = function()
    register("LvimQf", "quick_fix")
    register("LvimLoc", "loc")
end

return M
