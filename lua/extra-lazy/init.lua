-- extra-lazy.nvim: Enhanced editor mode for LazyVim
-- Inspired by ox (github.com/curlpipe/ox) and novim (github.com/link2004/novim)
-- Key features: Ctrl+S save, Ctrl+Q quit, type-to-edit, mouse-driven operation

local M = {}

function M.setup()
  -- Disable terminal XON/XOFF flow control so Ctrl+S and Ctrl+Q
  -- aren't intercepted by the terminal (common cause of "freeze").
  vim.fn.system({ "stty", "-ixon" })

  ----------------------------------------------------------------------
  -- 1. Display & Editor Options
  ----------------------------------------------------------------------
  vim.opt.mouse = "a"
  vim.opt.mousemodel = "extend"
  vim.opt.clipboard = "unnamedplus"
  vim.opt.showmode = false
  vim.opt.virtualedit = "onemore"
  vim.opt.backspace = { "indent", "eol", "start" }

  ----------------------------------------------------------------------
  -- 2. Autocommands
  ----------------------------------------------------------------------
  local augroup = vim.api.nvim_create_augroup("extra_lazy", { clear = true })

  -- Mouse double-click opens file/folder under cursor in netrw
  vim.api.nvim_create_autocmd("FileType", {
    group = augroup,
    pattern = "netrw",
    callback = function()
      vim.keymap.set("n", "<2-LeftMouse>", "<CR>", { buffer = true, silent = true })
    end,
  })

  -- Track changed lines with green highlights (like ox/novim)
  local changed_hl_ns = vim.api.nvim_create_namespace("extra_lazy_changed_lines")
  local changed_bufs = {}

  vim.api.nvim_create_autocmd("TextChangedI", {
    group = augroup,
    pattern = "*",
    callback = function()
      local line = vim.fn.line(".")
      local buf = vim.api.nvim_get_current_buf()
      changed_bufs[buf] = changed_bufs[buf] or {}
      if not changed_bufs[buf][line] then
        changed_bufs[buf][line] = true
        pcall(vim.api.nvim_buf_add_highlight, buf, changed_hl_ns, "DiffAdd", line - 1, 0, -1)
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufWritePost", {
    group = augroup,
    pattern = "*",
    callback = function()
      local buf = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_clear_namespace(buf, changed_hl_ns, 0, -1)
      changed_bufs[buf] = {}
    end,
  })

  -- Dynamic hints for statusline
  ---@diagnostic disable-next-line: lowercase-global
  function _G.extra_lazy_hints()
    local mode = vim.fn.mode()
    local modified = vim.bo.modified
    if mode == "v" or mode == "V" or mode == "\22" then
      return "^C Copy  ^X Cut  ^A All"
    elseif modified then
      return "^S Save  ^Z Undo  ^Q Quit"
    else
      return "^V Paste  ^A All  ^Q Quit"
    end
  end

  ----------------------------------------------------------------------
  -- 3. Global Keymaps (override LazyVim defaults)
  ----------------------------------------------------------------------
  local function stop()
    vim.cmd("stopinsert")
  end

  local function try_quit()
    local unsaved = false
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].modified then
        unsaved = true
        break
      end
    end
    if not unsaved then
      vim.cmd("qa")
      return
    end
    vim.ui.select(
      { "Save and Quit", "Quit without Saving", "Cancel" },
      { prompt = "You have unsaved changes:" },
      function(choice)
        if choice == "Save and Quit" then
          vim.cmd("wa")
          vim.cmd("qa")
        elseif choice == "Quit without Saving" then
          vim.cmd("qa!")
        end
      end
    )
  end

  local function open_cmdline()
    stop()
    vim.cmd("normal! :")
  end

  -- Ctrl+S: Save file
  vim.keymap.set({ "n", "i", "v", "s" }, "<C-s>", function()
    if vim.fn.mode():find("i") then
      vim.cmd("stopinsert")
    end
    local ok, err = pcall(vim.cmd, "w")
    if ok then
      vim.api.nvim_echo({ { "Saved!", "String" } }, false, {})
    elseif err then
      local msg = tostring(err):gsub("^Vim:%w+:", ""):gsub("^%s+", "")
      vim.api.nvim_echo({ { "Error saving: " .. msg, "ErrorMsg" } }, false, {})
    end
  end, { desc = "Save File" })

  -- Ctrl+Q: Quit
  vim.keymap.set({ "n", "i", "v" }, "<C-q>", try_quit, { desc = "Quit" })

  -- Ctrl+N: New file
  vim.keymap.set({ "n", "i", "v" }, "<C-n>", function()
    stop()
    vim.cmd("enew")
  end, { desc = "New File" })

  -- Ctrl+O: Open file
  vim.keymap.set({ "n", "i", "v" }, "<C-o>", function()
    stop()
    vim.ui.input({ prompt = "Open file: " }, function(input)
      if input and input ~= "" then
        vim.cmd.e({ args = { input } })
      end
    end)
  end, { desc = "Open File" })

  -- Ctrl+Z: Undo (overrides terminal suspend)
  vim.keymap.set({ "n", "i", "v" }, "<C-z>", function()
    stop()
    vim.cmd("undo")
  end, { desc = "Undo" })

  -- Ctrl+Y: Redo
  vim.keymap.set({ "n", "i", "v" }, "<C-y>", function()
    stop()
    vim.cmd("redo")
  end, { desc = "Redo" })

  -- Ctrl+A: Select all
  vim.keymap.set({ "n", "i", "v" }, "<C-a>", function()
    stop()
    vim.cmd("normal! ggVG")
  end, { desc = "Select All" })

  -- Ctrl+F: Search with Telescope
  vim.keymap.set({ "n", "i", "v" }, "<C-f>", function()
    stop()
    local ok = pcall(function()
      require("telescope.builtin").live_grep()
    end)
    if not ok then
      vim.cmd("normal! /")
    end
  end, { desc = "Find in Files" })

  -- Ctrl+R: Find word under cursor
  vim.keymap.set({ "n", "i", "v" }, "<C-r>", function()
    stop()
    local ok = pcall(function()
      require("telescope.builtin").grep_string()
    end)
    if not ok then
      vim.ui.input({ prompt = "Search: " }, function(s)
        if s and s ~= "" then
          vim.fn.histadd("search", s)
          vim.fn.setreg("/", s)
          vim.cmd("normal! n")
        end
      end)
    end
  end, { desc = "Find Word Under Cursor" })

  -- Ctrl+D: Delete line (overrides scroll half-page)
  vim.keymap.set({ "n", "i" }, "<C-d>", function()
    stop()
    vim.cmd("normal! dd")
  end, { desc = "Delete Line" })

  -- Ctrl+G: Go to line (overrides LazyVim's git status)
  vim.keymap.set({ "n", "i", "v" }, "<C-g>", function()
    stop()
    vim.ui.input({ prompt = "Go to line: " }, function(input)
      local line = tonumber(input)
      if line and line > 0 then
        vim.api.nvim_win_set_cursor(0, { line, 0 })
      end
    end)
  end, { desc = "Go to Line" })

  -- Ctrl+K: Open command-line (overrides window-up)
  -- Set immediately for early coverage, then re-set on VeryLazy to beat
  -- LazyVim's own <C-k> (window-up) which also maps on VeryLazy.
  vim.keymap.set({ "n", "i" }, "<C-k>", open_cmdline, { desc = "Command Line" })

  -- ponytail: LazyVim overrides <C-k> on VeryLazy, so we re-map there too.
  -- Our autocmd is registered during plugin config (before VeryLazy fires
  -- in normal startup), so our callback runs after LazyVim's.
  vim.api.nvim_create_autocmd("User", {
    pattern = "VeryLazy",
    group = augroup,
    callback = function()
      vim.keymap.set({ "n", "i" }, "<C-k>", open_cmdline, { desc = "Command Line" })
    end,
  })

  -- Double-Esc: Quit (novim-style)
  vim.keymap.set("n", "<Esc><Esc>", try_quit, { desc = "Quit (double Esc)" })

  ----------------------------------------------------------------------
  -- 4. Type-to-Insert Mode
  ----------------------------------------------------------------------
  -- Every printable character in normal mode enters insert mode and types it
  local printable_chars = vim.split(
    " !\"#$%&'()*+,-./0123456789:;<=>@ABCDEFGHIJKLMNOPQRSTUVWXYZ[]^_`abcdefghijklmnopqrstuvwxyz{|}~",
    ""
  )
  for _, char in ipairs(printable_chars) do
    if char ~= "?" and char ~= "\\" then
      vim.keymap.set("n", char, "i" .. char, { noremap = true, desc = "" })
    end
  end

  ----------------------------------------------------------------------
  -- 5. Visual Mode: typing replaces selection
  ----------------------------------------------------------------------
  local v_chars = vim.split(
    " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[]^_`abcdefghijklmnopqrstuvwxyz{|}~",
    ""
  )
  for _, char in ipairs(v_chars) do
    if char ~= "\\" then
      vim.keymap.set("v", char, '"_c' .. char, { noremap = true, desc = "" })
    end
  end

  -- Visual mode Enter replaces selection with newline
  vim.keymap.set("v", "<CR>", '"_c<CR>', { noremap = true, desc = "" })
  vim.keymap.set("n", "<CR>", "i<CR>", { noremap = true, desc = "" })
  vim.keymap.set("n", "<BS>", "X", { desc = "Delete Character Backward" })
  vim.keymap.set("v", "<BS>", '"_d', { desc = "Delete Selection" })
  vim.keymap.set("v", "<Del>", '"_d', { desc = "Delete Selection" })

  ----------------------------------------------------------------------
  -- 6. Arrow-key Selection
  ----------------------------------------------------------------------
  for _, dir in ipairs({ { "Left", "h" }, { "Right", "l" }, { "Up", "k" }, { "Down", "j" } }) do
    vim.keymap.set("n", "<S-" .. dir[1] .. ">", "v" .. dir[2], { desc = "Select " .. dir[1] })
    vim.keymap.set("i", "<S-" .. dir[1] .. ">", "<Esc>v" .. dir[2], { desc = "Select " .. dir[1] })
    vim.keymap.set("v", "<S-" .. dir[1] .. ">", dir[2], { desc = "Extend Selection " .. dir[1] })
  end

  ----------------------------------------------------------------------
  -- 7. Clipboard Operations
  ----------------------------------------------------------------------
  vim.keymap.set("v", "<C-c>", '"+ygv', { desc = "Copy" })
  vim.keymap.set("v", "<C-x>", '"+x', { desc = "Cut" })
  vim.keymap.set("n", "<C-v>", '"+gP', { desc = "Paste" })
  vim.keymap.set("i", "<C-v>", '<C-r>+', { desc = "Paste" })
  vim.keymap.set("v", "<C-v>", '"+P', { desc = "Paste" })
end

return M
