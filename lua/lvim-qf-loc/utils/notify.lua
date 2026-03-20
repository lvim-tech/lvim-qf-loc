local levels = require("lvim-qf-loc.utils.levels")

---@param msg   string
---@param level string|integer|nil
return function(msg, level)
    local config = require("lvim-qf-loc.config")

    if not config.notify then
        return
    end

    if type(msg) ~= "string" or msg == "" then
        return
    end

    local level_num = levels.to_level_number(level)

    vim.schedule(function()
        pcall(vim.notify, msg, level_num, { title = "LVIM LIST" })
    end)
end
