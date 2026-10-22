local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)

vim.schedule(function()
  local attach = vim.api.nvim_buf_attach
  local ok, err = xpcall(function()
    vim.cmd("enew!")
    local plugin = require("extra-lazy")
    assert(_G.extra_lazy_hints() == "", "hints must be callable before setup")
    local attachments = 0
    local current = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_attach = function(buf, ...)
      if buf == current then
        attachments = attachments + 1
      end
      return attach(buf, ...)
    end
    plugin.setup()
    assert(_G.extra_lazy_hints() == "^V Paste  ^A All  ^Q Quit", "normal-mode hints")
    vim.api.nvim_exec_autocmds("BufEnter", { buffer = 0 })
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "before" })
    assert(_G.extra_lazy_hints() == "^S Save  ^Z Undo  ^Q Quit", "modified-buffer hints")
    local autocmds = vim.api.nvim_get_autocmds({ group = "extra_lazy" })
    local function mapping(mode, lhs)
      return vim.fn.maparg(lhs, mode, false, true)
    end
    local normal = mapping("n", "<C-d>")
    local insert = mapping("i", "<C-d>")
    assert(normal.desc == "Delete Line" and type(normal.callback) == "function")
    assert(insert.desc == "Delete Line" and insert.callback == normal.callback)
    for _, expected in ipairs({
      { "n", "<C-Left>", "b" },
      { "i", "<C-Left>", "<C-o>b" },
      { "v", "<C-Left>", "b" },
      { "n", "<C-Right>", "w" },
      { "i", "<C-Right>", "<C-o>w" },
      { "v", "<C-Right>", "w" },
      { "i", "<C-BS>", '<C-o>"_db' },
      { "n", "<C-Del>", '"_dw' },
    }) do
      local found = mapping(expected[1], expected[2])
      assert(found.rhs == expected[3], expected[1] .. " " .. expected[2])
    end

    plugin.setup()
    vim.api.nvim_exec_autocmds("BufEnter", { buffer = 0 })
    assert(attachments == 1, "setup attached duplicate buffer callbacks")
    assert(vim.deep_equal(autocmds, vim.api.nvim_get_autocmds({ group = "extra_lazy" })))
    assert(mapping("n", "<C-d>").callback == normal.callback)
    assert(mapping("i", "<C-d>").callback == insert.callback)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "after" })
    local ns = vim.api.nvim_get_namespaces().extra_lazy_changed_lines
    assert(#vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, {}) == 1, "changed line not tracked")
    vim.api.nvim_exec_autocmds("BufWritePost", { buffer = 0 })
    assert(#vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, {}) == 0, "save did not reset changed lines")
    local visual = mapping("x", "<C-d>")
    assert(visual.rhs == '"_d' and visual.noremap == 1)

    vim.opt.clipboard = ""
    local registers = {}
    for _, reg in ipairs({ "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "-", "a", '"' }) do
      vim.fn.setreg(reg, "keep " .. reg, "v")
      registers[reg] = true
    end
    for reg in pairs(registers) do
      registers[reg] = vim.fn.getreginfo(reg)
    end
    local function press(keys)
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "xt", false)
    end
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abcdef", "keep" })
    vim.api.nvim_win_set_cursor(0, { 1, 1 })
    vim.cmd("normal! v2l")
    press("<C-d>")
    assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "aef", "keep" }))
    assert(vim.fn.mode() == "n")
    press("<C-d>")
    assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "keep" }))
    press("i<C-d><Esc>")
    assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "" }))
    for reg, value in pairs(registers) do
      assert(vim.deep_equal(vim.fn.getreginfo(reg), value), "register changed: " .. reg)
    end

    -- Ctrl+S on an unnamed buffer asks for a path instead of failing with E32.
    local as_target = vim.fn.tempname() .. " sp ace#1%2.txt"
    vim.fn.writefile({ "old" }, as_target)
    local input = vim.ui.input
    local select = vim.ui.select
    vim.ui.input = function(_, callback)
      callback(as_target)
    end
    -- Cancelling the overwrite prompt leaves the existing file alone.
    vim.ui.select = function(_, _, callback)
      callback(nil)
    end
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "save me" })
    mapping("n", "<C-s>").callback()
    assert(vim.fn.readfile(as_target)[1] == "old", "cancel still overwrote the file")
    assert(vim.api.nvim_buf_get_name(0) == "", "cancel renamed the buffer")
    -- Confirming overwrites the existing file and names the buffer.
    vim.ui.select = function(_, _, callback)
      callback("Overwrite")
    end
    mapping("n", "<C-s>").callback()
    vim.ui.input = input
    vim.ui.select = select
    assert(vim.fn.readfile(as_target)[1] == "save me", "save-as did not overwrite/write the file")
    assert(vim.api.nvim_buf_get_name(0) == as_target, "save-as did not name the buffer")

    -- Ctrl+S on a named buffer writes without prompting.
    local prompted = false
    vim.ui.input = function()
      prompted = true
    end
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "again" })
    mapping("n", "<C-s>").callback()
    vim.ui.input = input
    assert(not prompted, "save prompted for a named buffer")
    assert(vim.fn.readfile(as_target)[1] == "again", "named save did not write")

    -- The save-as callback writes the buffer that asked, even if the prompt
    -- left another buffer current.
    local as2 = vim.fn.tempname()
    vim.cmd("enew")
    local asking_buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "target" })
    local other_buf = vim.api.nvim_create_buf(true, false)
    vim.ui.input = function(_, callback)
      vim.api.nvim_set_current_buf(other_buf)
      callback(as2)
    end
    mapping("n", "<C-s>").callback()
    vim.ui.input = input
    assert(vim.fn.readfile(as2)[1] == "target", "save-as wrote the wrong buffer")
    assert(vim.api.nvim_buf_get_name(asking_buf) == as2, "save-as did not name the asking buffer")
    assert(vim.api.nvim_buf_get_name(other_buf) == "", "save-as renamed an unrelated buffer")

    -- Undo clears changed-line highlights instead of marking the reverted line.
    local undo_target = vim.fn.tempname()
    vim.fn.writefile({ "one", "two" }, undo_target)
    vim.cmd.edit(undo_target)
    local ns = vim.api.nvim_get_namespaces().extra_lazy_changed_lines
    vim.api.nvim_buf_set_lines(0, 1, 2, false, { "changed" })
    assert(#vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, {}) == 1, "edit not tracked")
    vim.cmd("undo")
    -- headless -l never dispatches TextChanged, so fire it like the editor does.
    vim.api.nvim_exec_autocmds("TextChanged", { buffer = 0 })
    assert(#vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, {}) == 0, "undo left changed highlights")

    vim.api.nvim_buf_set_lines(0, 1, 2, false, { "changed again" })
    vim.api.nvim_exec_autocmds("TextChanged", { buffer = 0 })
    assert(#vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, {}) == 1, "modified buffer lost its marks")

    -- Type-to-insert still inserts in an editable file buffer, and typing over
    -- a selection still replaces it.
    vim.cmd("enew!")
    press("x")
    assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == "x", "type-to-insert did not insert")
    press("<Esc>")
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abc" })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.cmd("normal! v2l")
    press("z")
    assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == "z", "visual replace did not replace")
    press("<Esc>")

    -- Read-only buffers keep their normal keys: j scrolls help.
    vim.cmd("help")
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    press("j")
    assert(vim.fn.mode() == "n", "help: printable key left normal mode")
    assert(vim.api.nvim_win_get_cursor(0)[1] == 2, "help: j did not move")
    vim.cmd("helpclose")

    -- Ctrl+O opens paths with characters Ex treats specially.
    local open_target = vim.fn.tempname() .. " 100%#1.txt"
    vim.fn.writefile({ "opened" }, open_target)
    vim.ui.input = function(_, callback)
      callback(open_target)
    end
    mapping("n", "<C-o>").callback()
    vim.ui.input = input
    assert(vim.api.nvim_buf_get_name(0) == open_target, "Ctrl+O did not open " .. open_target)

    -- Save-as checks and writes the same expanded path, so $VAR names do not
    -- silently overwrite the literal file.
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    vim.env.EXTRA_LAZY_TEST = "target"
    local literal = dir .. "/x$EXTRA_LAZY_TEST"
    local expanded = dir .. "/xtarget"
    vim.fn.writefile({ "OLD" }, literal)
    vim.fn.writefile({ "OLD" }, expanded)
    vim.cmd("enew!")
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "NEW" })
    vim.ui.input = function(_, callback)
      callback(literal)
    end
    vim.ui.select = function(_, _, callback)
      callback("Overwrite")
    end
    mapping("n", "<C-s>").callback()
    vim.ui.input, vim.ui.select = input, select
    vim.env.EXTRA_LAZY_TEST = nil
    assert(vim.fn.readfile(expanded)[1] == "NEW", "save-as did not write the expanded path")
    assert(vim.fn.readfile(literal)[1] == "OLD", "save-as overwrote the literal path")

    -- Changed-line marks follow text when lines are inserted above them.
    local shift_target = vim.fn.tempname()
    local body = {}
    for i = 1, 30 do
      body[i] = "line " .. i
    end
    vim.fn.writefile(body, shift_target)
    vim.cmd.edit(shift_target)
    vim.api.nvim_buf_set_lines(0, 9, 10, false, { "changed" })
    vim.api.nvim_buf_set_lines(0, 0, 0, false, { "a", "b", "c", "d", "e" })
    vim.api.nvim_buf_set_lines(0, 9, 10, false, { "changed later" })
    assert(#vim.api.nvim_buf_get_extmarks(0, ns, { 9, 0 }, { 9, -1 }, {}) == 1, "shifted line not marked")

    plugin._reset()
    local word_keys = { "<C-Left>", "<C-Right>", "<C-BS>", "<C-Del>" }
    for _, mode in ipairs({ "n", "i", "v" }) do
      for _, lhs in ipairs(word_keys) do
        pcall(vim.keymap.del, mode, lhs)
      end
    end
    plugin.setup({ word_movement = false })
    for _, mode in ipairs({ "n", "i", "v" }) do
      for _, lhs in ipairs(word_keys) do
        assert(next(mapping(mode, lhs)) == nil, "disabled word mapping: " .. mode .. " " .. lhs)
      end
    end
    assert(mapping("n", "<C-d>").desc == "Delete Line")

    -- _reset()+setup() must not leave a second changed-line watcher.
    vim.api.nvim_exec_autocmds("BufWritePost", { buffer = 0 })
    vim.api.nvim_buf_set_lines(0, 20, 21, false, { "reloaded" })
    assert(
      #vim.api.nvim_buf_get_extmarks(0, ns, { 20, 0 }, { 20, -1 }, {}) == 1,
      "reload duplicated changed-line marks"
    )

    plugin._reset()
    for _, mode in ipairs({ "n", "i", "v" }) do
      pcall(vim.keymap.del, mode, "<C-d>")
    end
    plugin.setup({ keymaps = { ["<C-d>"] = "<C-x>" } })
    assert(mapping("n", "<C-x>").desc == "Delete Line")
    assert(mapping("i", "<C-x>").desc == "Delete Line")
    assert(mapping("v", "<C-x>").rhs == '"_d')
  end, debug.traceback)
  vim.api.nvim_buf_attach = attach
  if not ok then
    vim.api.nvim_err_writeln(err)
    vim.cmd("cquit 1")
  else
    print("smoke: OK")
    vim.cmd("qa!")
  end
end)
