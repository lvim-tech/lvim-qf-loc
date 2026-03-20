-- Unified tabs popup for LvimQf / LvimLoc.
-- All tabs use action rows so keymaps are bound consistently at attach time.

local utils = require("lvim-qf-loc.utils")
local config = require("lvim-qf-loc.config")
local nav = require("lvim-qf-loc.core.nav")
local diagnostics = require("lvim-qf-loc.core.diagnostics")

local function tab_icon(name)
    local t = config.tabs and config.tabs[name]
    return t and t.icon or nil
end

local M = {}

-- ── helpers ────────────────────────────────────────────────────────────────

local function action(label, fn)
    return {
        type = "action",
        label = label,
        run = function(_, close)
            fn()
            close(false, nil)
        end,
    }
end

local function spacer()
    return { type = "spacer", label = "" }
end

-- ── tab builders ───────────────────────────────────────────────────────────

local function nav_tab(kind)
    local is_qf = kind == "quick_fix"
    return {
        label = "Navigate",
        icon = tab_icon("navigate"),
        rows = {
            action("Open", is_qf and nav.quick_fix_open or nav.loc_list_open),
            action("Close", is_qf and nav.quick_fix_close or nav.loc_list_close),
            spacer(),
            action("Next", is_qf and nav.quick_fix_next or nav.loc_list_next),
            action("Previous", is_qf and nav.quick_fix_prev or nav.loc_list_prev),
        },
    }
end

local function choice_tab(kind)
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
                local newer = kind == "quick_fix" and "cnewer" or "lnewer"
                local older = kind == "quick_fix" and "colder" or "lolder"
                local open = kind == "quick_fix" and "copen" or "lopen"
                local diff = idx - current_nr
                if diff > 0 then
                    for _ = 1, diff do
                        vim.cmd("silent " .. newer)
                    end
                elseif diff < 0 then
                    for _ = 1, -diff do
                        vim.cmd("silent " .. older)
                    end
                end
                vim.cmd("silent " .. open)
                utils.notify("Switched to: " .. title)
                close(false, nil)
            end,
        })
    end
    if #rows == 0 then
        rows = { { type = "text", label = "No lists available" } }
    end
    return { label = "Switch", icon = tab_icon("switch"), rows = rows }
end

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
        rows = { { type = "text", label = "No lists available" } }
    end
    return { label = "Delete", icon = tab_icon("delete"), rows = rows }
end

local function storage_tab(kind, filename, setfn)
    return {
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
                        setfn(0, {}, " ", data[i])
                    end
                    utils.notify("Loaded " .. tostring(len) .. " list(s)")
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

local function diagnostics_tab()
    return {
        label = "Diagnostics",
        icon = tab_icon("diagnostics"),
        rows = { action("Load diagnostics", diagnostics.qf_diagnostics) },
    }
end

-- ── public ─────────────────────────────────────────────────────────────────

local function open(kind, tab_selector)
    local instance = require("lvim-qf-loc.ui").get()
    if not instance then
        return
    end

    local filename = kind == "quick_fix" and ".lvim_qf.json" or ".lvim_loc.json"
    local setfn = kind == "quick_fix" and vim.fn.setqflist or vim.fn.setloclist
    local title = kind == "quick_fix" and "Quickfix" or "Location"

    local tabs = {
        nav_tab(kind),
        choice_tab(kind),
        delete_tab(kind),
        storage_tab(kind, filename, setfn),
    }
    if kind == "quick_fix" then
        table.insert(tabs, diagnostics_tab())
    end

    instance.tabs({
        title = title,
        tab_selector = tab_selector,
        tabs = tabs,
        callback = function() end,
    })
end

M.open_qf = function(tab_selector)
    open("quick_fix", tab_selector)
end
M.open_loc = function(tab_selector)
    open("loc", tab_selector)
end

return M
