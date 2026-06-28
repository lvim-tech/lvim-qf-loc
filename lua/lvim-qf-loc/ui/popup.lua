-- lua/lvim-qf-loc/ui/popup.lua
-- The LvimQf / LvimLoc MANAGEMENT popup — a tabbed menu (lvim-utils.ui.tabs in `menu` mode, so each tab's rows
-- are a navigable BODY list) over the stored quickfix / location lists. Three tabs:
--   Browse  — every stored list; pick one → switch to it (relative `:cnewer`/`:colder`) + open the live-preview
--             browser of its entries
--   Delete  — remove a stored list
--   Storage — save / load all lists to a per-project JSON, show the cwd
-- Opened by `:LvimQf` / `:LvimQf browse|delete|storage` (+ the LvimLoc twins). The list NAVIGATION actions
-- (open/close/next/prev) and `diagnostics` are DIRECT commands, NOT tabs — see hooks/commands.lua.
--
---@module "lvim-qf-loc.ui.popup"

local utils = require("lvim-qf-loc.utils")
local config = require("lvim-qf-loc.config")

local M = {}

--- The configured Nerd-font icon for tab `name` (config.tabs[name].icon), or nil.
---@param name string
---@return string?
local function tab_icon(name)
    local t = config.tabs and config.tabs[name]
    return t and t.icon or nil
end

local function spacer()
    return { type = "spacer", label = "" }
end

-- ── tab builders ───────────────────────────────────────────────────────────

--- Browse: list every stored quickfix/location list; choosing one switches to it (relative `:cnewer`/`:colder`)
--- and opens the live-preview BROWSER of its entries. `loclist_win` is nil for the quickfix.
---@param kind "quick_fix"|"loc"
---@param loclist_win integer?
---@return table tab
local function browse_tab(kind, loclist_win)
    local len = utils.length(kind)
    local current_nr = utils.current(kind)
    local newer = kind == "quick_fix" and "cnewer" or "lnewer"
    local older = kind == "quick_fix" and "colder" or "lolder"
    local rows = {}
    for i = 1, len do
        local title = utils.title(kind, i)
        local label = i == current_nr and (title .. " (current)") or title
        local idx = i
        table.insert(rows, {
            type = "action",
            label = label,
            run = function(_, close)
                local diff = idx - current_nr
                for _ = 1, diff do
                    vim.cmd("silent " .. newer)
                end
                for _ = 1, -diff do
                    vim.cmd("silent " .. older)
                end
                close(false, nil)
                require("lvim-qf-loc.qf.browser").open(loclist_win)
            end,
        })
    end
    if #rows == 0 then
        rows = { { type = "action", flat = true, tight = true, label = "No lists available" } }
    end
    return { name = "browse", label = "Browse", icon = tab_icon("browse"), rows = rows }
end

--- Delete: remove a stored list. Deleting the CURRENT one closes its window first; deleting the "Diagnostics"
--- list clears the active flag so the DiagnosticChanged reload stops tracking it.
---@param kind "quick_fix"|"loc"
---@return table tab
local function delete_tab(kind)
    local len = utils.length(kind)
    local current_nr = utils.current(kind)
    local rows = {}
    for i = 1, len do
        local title = utils.title(kind, i)
        local label = i == current_nr and (title .. " (current)") or title
        local idx = i
        table.insert(rows, {
            type = "action",
            label = label,
            run = function(_, close)
                if idx == current_nr then
                    vim.cmd("silent " .. (kind == "quick_fix" and "cclose" or "lclose"))
                end
                local updated = {}
                for j = 1, len do
                    if j ~= idx then
                        table.insert(updated, utils.list_to_json(kind, j))
                    elseif kind == "quick_fix" and utils.title("quick_fix", j) == "Diagnostics" then
                        config.is_active = false
                    end
                end
                if kind == "quick_fix" then
                    vim.fn.setqflist({}, "f")
                    for _, qf in ipairs(updated) do
                        vim.fn.setqflist({}, " ", qf)
                    end
                else
                    vim.fn.setloclist(0, {}, "f")
                    for _, loc in ipairs(updated) do
                        vim.fn.setloclist(0, {}, " ", loc)
                    end
                end
                utils.notify("Deleted: " .. title)
                close(false, nil)
            end,
        })
    end
    if #rows == 0 then
        rows = { { type = "action", flat = true, tight = true, label = "No lists available" } }
    end
    return { name = "delete", label = "Delete", icon = tab_icon("delete"), rows = rows }
end

--- Storage: save all lists to / load them from a per-project JSON (`filename`), and show the cwd.
---@param kind "quick_fix"|"loc"
---@param filename string
---@param setfn fun(list: table, action: string, what: table)  normalised qf/loc setter (window arg hidden)
---@return table tab
local function storage_tab(kind, filename, setfn)
    return {
        name = "storage",
        label = "Storage",
        icon = tab_icon("storage"),
        rows = {
            {
                type = "action",
                label = "Save",
                run = function(_, close)
                    local len = utils.length(kind)
                    if len < 1 then
                        utils.notify("No " .. kind .. " lists to save")
                        close(false, nil)
                        return
                    end
                    local data = {}
                    for i = 1, len do
                        table.insert(data, utils.list_to_json(kind, i))
                    end
                    utils.write_file(vim.fn.getcwd() .. "/" .. filename, data)
                    utils.notify("Saved to " .. filename)
                    close(false, nil)
                end,
            },
            {
                type = "action",
                label = "Load",
                run = function(_, close)
                    local data = utils.read_file(vim.fn.getcwd() .. "/" .. filename)
                    if not data then
                        utils.notify("No saved lists found")
                        close(false, nil)
                        return
                    end
                    local len = utils.table_length(data)
                    for i = 1, len do
                        setfn({}, " ", data[i])
                    end
                    utils.notify("Loaded " .. tostring(len) .. " list(s)")
                    close(false, nil)
                end,
            },
            {
                type = "action",
                label = "Delete",
                run = function(_, close)
                    if utils.delete_file(vim.fn.getcwd() .. "/" .. filename) then
                        utils.notify("Deleted " .. filename)
                    else
                        utils.notify("No saved lists found")
                    end
                    close(false, nil)
                end,
            },
            spacer(),
            {
                type = "action",
                label = "Show path",
                run = function(_, close)
                    utils.notify(vim.fn.getcwd())
                    close(false, nil)
                end,
            },
        },
    }
end

-- ── public ─────────────────────────────────────────────────────────────────

--- Open the management popup on `tab_selector` (a tab `name`: "browse"|"delete"|"storage"; nil → the first tab,
--- Browse). `loclist_win` is the window whose location list to act on (nil for the quickfix).
---@param kind "quick_fix"|"loc"
---@param tab_selector string?
---@param loclist_win integer?
local function open(kind, tab_selector, loclist_win)
    local instance = require("lvim-qf-loc.ui").get()
    if not instance then
        return
    end
    local filename = kind == "quick_fix" and ".lvim_qf.json" or ".lvim_loc.json"
    -- Normalised setter to ONE `(list, action, what)` signature: `setqflist` takes those three, but
    -- `setloclist` prepends a window-number arg — so calling the raw fn with a leading `0` blew up `setqflist`
    -- with "too many arguments" (the Quickfix → Load path). The wrapper hides that difference.
    local setfn
    if kind == "quick_fix" then
        setfn = function(list, action, what)
            return vim.fn.setqflist(list, action, what)
        end
    else
        setfn = function(list, action, what)
            return vim.fn.setloclist(0, list, action, what)
        end
    end
    local title = kind == "quick_fix" and "Quickfix" or "Location"
    instance.tabs({
        title = title,
        tab_selector = tab_selector,
        menu = true, -- every tab is a navigable MENU: its action rows are a selectable BODY list, not footer chips
        width = config.popup_global.width,
        footer_hints = true, -- bottom key-hint legend (panel keys • focused-row keys), like the control center
        -- add a BOTTOM edge (" ") so the content gets a closing border row below it (the frame defaults to none)
        border = { "", " ", "", " ", "", " ", "", " " },
        tabs = {
            browse_tab(kind, loclist_win),
            delete_tab(kind),
            storage_tab(kind, filename, setfn),
        },
        callback = function() end,
    })
end

M.open = open

return M
