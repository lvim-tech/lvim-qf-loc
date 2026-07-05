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
    local ok_frame, frame = pcall(require, "lvim-ui.surface")
    local ok_hl, uhl = pcall(require, "lvim-utils.highlight")
    local ok_c, C = pcall(require, "lvim-utils.colors")
    if not (ok_frame and ok_hl and ok_c and C.blue) then
        return
    end
    local function mtint(color, t)
        return uhl.blend(color, C.bg, t)
    end
    -- Key box = 0.4 (bold); description box = 0.2, rising to 0.4 on the ACTIVE row (whole-row solid tint).
    api.nvim_set_hl(0, "LvimQfLocHelpKeyB", { fg = C.blue, bg = mtint(C.blue, 0.4), bold = true })
    api.nvim_set_hl(0, "LvimQfLocHelpDescB", { fg = C.blue, bg = mtint(C.blue, 0.2) })
    api.nvim_set_hl(0, "LvimQfLocHelpDescActiveB", { fg = C.blue, bg = mtint(C.blue, 0.4) })
    api.nvim_set_hl(0, "LvimQfLocHelpKeyY", { fg = C.yellow, bg = mtint(C.yellow, 0.4), bold = true })
    api.nvim_set_hl(0, "LvimQfLocHelpDescY", { fg = C.yellow, bg = mtint(C.yellow, 0.2) })
    api.nvim_set_hl(0, "LvimQfLocHelpDescActiveY", { fg = C.yellow, bg = mtint(C.yellow, 0.4) })

    local items = entries()
    local kw, dw = 0, 0
    for _, r in ipairs(items) do
        kw = math.max(kw, vim.fn.strdisplaywidth(r[1]))
        dw = math.max(dw, vim.fn.strdisplaywidth(r[2]))
    end
    local keybox = kw + 4 -- 2 spaces left of the key + key + ≥2 right — the fixed, aligned KEY column

    local pan
    local provider = {
        hide_cursor = true,
        size = function()
            return keybox + dw + 4, #items
        end,
        render = function(width)
            local cur = (pan and pan.win and api.nvim_win_is_valid(pan.win)) and api.nvim_win_get_cursor(pan.win)[1]
                or 1
            local lines, hls = {}, {}
            for i, r in ipairs(items) do
                local s = (i % 2 == 1) and "B" or "Y" -- odd = blue, even = yellow
                local kcell = "  " .. r[1]
                kcell = kcell .. string.rep(" ", math.max(0, keybox - #kcell))
                local dcell = "  " .. r[2]
                dcell = dcell .. string.rep(" ", math.max(0, width - keybox - #dcell))
                lines[i] = kcell .. dcell
                local desc = (i == cur) and ("LvimQfLocHelpDescActive" .. s) or ("LvimQfLocHelpDesc" .. s)
                hls[#hls + 1] = { i - 1, 0, #kcell, "LvimQfLocHelpKey" .. s }
                hls[#hls + 1] = { i - 1, #kcell, #lines[i], desc }
            end
            return lines, hls
        end,
        keys = function(_, p)
            pan = p
            api.nvim_create_autocmd("CursorMoved", {
                buffer = p.buf,
                callback = function()
                    if p.refresh then
                        p.refresh()
                    end
                end,
            })
        end,
    }
    local close = { "<Esc>", "q" }
    if config.edit.keys and config.edit.keys.help then
        close[#close + 1] = config.edit.keys.help
    end
    frame.open({
        mode = "float",
        -- the help-window canon: a top " " edge ONLY (no ring) that carries the native, blue-tinted border-title
        border = { "", " ", "", "", "", "", "", "" },
        title = "QUICKFIX KEYMAPS",
        panel_border = "none",
        size = { width = { auto = true, max = 0.7 }, height = { auto = true, max = 0.7 } },
        close_keys = close,
        content = { blocks = { { id = "help", provider = provider } } },
        footer = {
            bars = {
                {
                    items = {
                        {
                            key = "q",
                            name = "close",
                            run = function(st)
                                st.close()
                            end,
                        },
                    },
                },
            },
        },
    })
end

return M
