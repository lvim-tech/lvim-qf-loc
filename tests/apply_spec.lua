-- Writing somebody's files, with the guards that make it safe to do at all.
--
-- apply_changes is the shared core behind both the editable quickfix and search&replace, and its
-- contract is a refusal: a line is written ONLY when the file's current text still equals what the
-- list SHOWED. Anything else -- the file changed on disk, another buffer edited it, the entry is
-- stale -- is skipped and counted, never clobbered. The autosave policy is the second guard: a
-- file the user already had unsaved changes in is not saved behind their back.

local edit = require("lvim-qf-loc.qf.edit")
local config = require("lvim-qf-loc.config")

--- A file on disk holding `lines`, in a directory of its own.
---@param lines string[]
---@param name? string
---@return string path
local function file_with(lines, name)
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    local path = dir .. "/" .. (name or "subject.txt")
    vim.fn.writefile(lines, path)
    return path
end

--- Wipe any buffer holding `path`, so the next apply loads it fresh from disk.
---@param path string
local function forget(path)
    local buf = vim.fn.bufnr(vim.fn.fnameescape(path))
    if buf ~= -1 and vim.api.nvim_buf_is_valid(buf) then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
end

--- Run apply_changes with a given autosave policy.
---@param changes table
---@param policy boolean|string
---@return integer applied, integer skipped
local function apply_with(changes, policy)
    local was = config.edit.autosave
    config.edit.autosave = policy
    local applied, skipped = edit.apply_changes(changes)
    config.edit.autosave = was
    return applied, skipped
end

describe("lvim-qf-loc: applying an edit to a source line")

it("a line that still matches what was shown is written", function()
    local path = file_with({ "one", "two", "three" })
    forget(path)
    local applied, skipped = apply_with({ [path] = { [2] = { orig = "two", new = "TWO" } } }, true)
    eq(1, applied)
    eq(0, skipped)
    eq({ "one", "TWO", "three" }, vim.fn.readfile(path))
    forget(path)
end)

it("a line that changed since the list was built is skipped, not clobbered", function()
    local path = file_with({ "one", "two", "three" })
    forget(path)
    local applied, skipped = apply_with({ [path] = { [2] = { orig = "something else", new = "TWO" } } }, true)
    eq(0, applied)
    eq(1, skipped, "the entry is stale; the only safe thing is to refuse it")
    eq({ "one", "two", "three" }, vim.fn.readfile(path), "the file is exactly as it was")
    forget(path)
end)

it("the safe lines of a file are applied while the stale ones are skipped", function()
    local path = file_with({ "a", "b", "c" })
    forget(path)
    local applied, skipped = apply_with({
        [path] = {
            [1] = { orig = "a", new = "A" },
            [2] = { orig = "NOT b", new = "B" },
            [3] = { orig = "c", new = "C" },
        },
    }, true)
    eq(2, applied)
    eq(1, skipped)
    eq({ "A", "b", "C" }, vim.fn.readfile(path), "one stale entry must not cost the others")
    forget(path)
end)

it("several files are written in one pass", function()
    local a = file_with({ "x" }, "a.txt")
    local b = file_with({ "y" }, "b.txt")
    forget(a)
    forget(b)
    local applied = apply_with({
        [a] = { [1] = { orig = "x", new = "X" } },
        [b] = { [1] = { orig = "y", new = "Y" } },
    }, true)
    eq(2, applied)
    eq({ "X" }, vim.fn.readfile(a))
    eq({ "Y" }, vim.fn.readfile(b))
    forget(a)
    forget(b)
end)

it("a line number past the end of the file is skipped", function()
    local path = file_with({ "only" })
    forget(path)
    local applied, skipped = apply_with({ [path] = { [99] = { orig = "only", new = "nope" } } }, true)
    eq(0, applied)
    eq(1, skipped, "there is no line 99 to compare against")
    eq({ "only" }, vim.fn.readfile(path))
    forget(path)
end)

it("an empty change set writes nothing and reports nothing", function()
    eq({ 0, 0 }, { apply_with({}, true) })
end)

describe("lvim-qf-loc: the autosave policy")

it("with autosave on, the file on disk carries the change", function()
    local path = file_with({ "before" })
    forget(path)
    apply_with({ [path] = { [1] = { orig = "before", new = "after" } } }, true)
    eq({ "after" }, vim.fn.readfile(path))
    forget(path)
end)

it("with autosave off, the buffer carries the change and the disk does not", function()
    local path = file_with({ "before" })
    forget(path)
    apply_with({ [path] = { [1] = { orig = "before", new = "after" } } }, false)

    eq({ "before" }, vim.fn.readfile(path), "nothing was written to disk")
    local buf = vim.fn.bufnr(vim.fn.fnameescape(path))
    truthy(buf ~= -1, "the edit has to be SOMEWHERE")
    eq({ "after" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false), "it is in the buffer, for the user to save")
    forget(path)
end)

it("the unmodified policy leaves a file the user is already editing alone", function()
    local path = file_with({ "before" })
    forget(path)

    -- The user has this file open with unsaved changes of their own.
    local buf = vim.fn.bufadd(path)
    vim.fn.bufload(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "before", "their own unsaved line" })
    eq(true, vim.bo[buf].modified, "precondition: the buffer is dirty")

    apply_with({ [path] = { [1] = { orig = "before", new = "after" } } }, "unmodified")

    eq({ "before" }, vim.fn.readfile(path), "saving here would write the user's unsaved work for them")
    eq("after", vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1], "the edit still landed in the buffer")
    eq(true, vim.bo[buf].modified)
    forget(path)
end)

it("the unmodified policy does save a file that was clean", function()
    local path = file_with({ "before" })
    forget(path)
    apply_with({ [path] = { [1] = { orig = "before", new = "after" } } }, "unmodified")
    eq({ "after" }, vim.fn.readfile(path), "nothing of the user's was at stake, so it is saved")
    forget(path)
end)

it("a file that cannot be read is skipped rather than created", function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    local path = dir .. "/never-existed.txt"
    local applied, skipped = apply_with({ [path] = { [1] = { orig = "anything", new = "x" } } }, true)
    eq(0, applied)
    eq(1, skipped)
    eq(0, vim.fn.filereadable(path), "an edit to a list entry must not conjure a file")
end)
