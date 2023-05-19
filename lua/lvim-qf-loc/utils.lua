local M = {}

M.table_length = function(tbl)
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

M.length = function(list)
    if list == "quick_fix" then
        return vim.fn.getqflist({ nr = "$" })["nr"]
    elseif list == "loc" then
        return vim.fn.getloclist(0, { nr = "$" })["nr"]
    end
end

M.current = function(list)
    if list == "quick_fix" then
        return vim.fn.getqflist({ nr = 0 })["nr"]
    elseif list == "loc" then
        return vim.fn.getloclist(0, { nr = 0 })["nr"]
    end
end

M.title = function(list, id)
    if list == "quick_fix" then
        return vim.fn.getqflist({ nr = id, all = 1 })["title"]
    elseif list == "loc" then
        return vim.fn.getloclist(0, { nr = id, all = 1 })["title"]
    end
end

M.list_fix = function(list)
    for i, d in ipairs(list.items) do
        if vim.api.nvim_buf_is_valid(d.bufnr) then
            d.filename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(d.bufnr), ":p")
        end
        d.bufnr = nil
        d.nr = nil
        list.items[i] = d
    end
    local clear_list = {
        title = list.title,
        items = list.items,
    }
    return clear_list
end

M.list_to_json = function(list, id)
    local list_content
    if list == "quick_fix" then
        list_content = vim.fn.getqflist({ nr = id, all = 1 })
    elseif list == "loc" then
        list_content = vim.fn.getloclist(0, { nr = id, all = 1 })
    end
    return M.list_fix(list_content)
end

M.read_file = function(file)
    local content
    local file_content_ok, _ = pcall(function()
        content = vim.fn.readfile(file)
    end)
    if not file_content_ok then
        return nil
    end
    if type(content) == "table" then
        return vim.fn.json_decode(content)
    else
        return nil
    end
end

M.write_file = function(file, content)
    local f = io.open(file, "w")
    if f ~= nil then
        if type(content) == "table" then
            content = vim.fn.json_encode(content)
        end
        f:write(content)
        f:close()
    end
end

M.delete_file = function(f)
    os.remove(f)
end

M.create_dir = function(dirname)
    os.execute("mkdir " .. dirname)
end

M.exists = function(name)
    local f = io.open(name, "r")
    if f ~= nil then
        io.close(f)
        return true
    else
        return false
    end
end
return M
