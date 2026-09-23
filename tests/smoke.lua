local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)

vim.schedule(function()
  local attach = vim.api.nvim_buf_attach
  local ok, err = xpcall(function()
    vim.cmd("enew!")
    local plugin = require("extra-lazy")
    local attachments = 0
    local current = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_attach = function(buf, ...)
      if buf == current then
        attachments = attachments + 1
      end
      return attach(buf, ...)
    end
    plugin.setup()
    vim.api.nvim_exec_autocmds("BufEnter", { buffer = 0 })
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "before" })
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
