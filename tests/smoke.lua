vim.opt.runtimepath:prepend(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h"))

vim.schedule(function()
  local ok, err = xpcall(function()
    local plugin = require("extra-lazy")
    local attach = vim.api.nvim_buf_attach
    local attachments = 0
    vim.api.nvim_buf_attach = function(...)
      attachments = attachments + 1
      return attach(...)
    end
    plugin.setup()
    vim.api.nvim_exec_autocmds("BufEnter", { buffer = 0 })
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "before" })
    local autocmds = vim.api.nvim_get_autocmds({ group = "extra_lazy" })
    local normal = vim.fn.maparg("<C-d>", "n", false, true)
    local insert = vim.fn.maparg("<C-d>", "i", false, true)
    assert(normal.desc == "Delete Line" and type(normal.callback) == "function")
    assert(insert.desc == "Delete Line" and insert.callback == normal.callback)

    plugin.setup()
    vim.api.nvim_exec_autocmds("BufEnter", { buffer = 0 })
    vim.api.nvim_buf_attach = attach
    assert(attachments == 1, "setup attached duplicate buffer callbacks")
    assert(vim.deep_equal(autocmds, vim.api.nvim_get_autocmds({ group = "extra_lazy" })))
    assert(vim.fn.maparg("<C-d>", "n", false, true).callback == normal.callback)
    assert(vim.fn.maparg("<C-d>", "i", false, true).callback == insert.callback)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "after" })
    local ns = vim.api.nvim_get_namespaces().extra_lazy_changed_lines
    assert(#vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, {}) == 1, "tracking state reset")
    local visual = vim.fn.maparg("<C-d>", "x", false, true)
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
  end, debug.traceback)
  if not ok then
    vim.api.nvim_err_writeln(err)
    vim.cmd("cquit 1")
  else
    print("smoke: OK")
    vim.cmd("qa!")
  end
end)
