-- extra-lazy.nvim: Enhanced editor mode for LazyVim
-- Inspired by ox (github.com/curlpipe/ox) and novim (github.com/link2004/novim)
-- Key features: Ctrl+S save, Ctrl+Q quit, type-to-edit, mouse-driven operation

local M = {}

function M.setup()
  ----------------------------------------------------------------------
  -- 1. Display & Editor Options
  ----------------------------------------------------------------------
  vim.opt.mouse = "a"
  vim.opt.mousemodel = "extend"
  vim.opt.clipboard = "unnamedplus"
  vim.opt.showmode = false
  vim.opt.virtualedit = "onemore"

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
  -- ponytail: on_lines gives the exact edited range; cursor-line-only
  -- marking missed multi-line pastes.
  local changed_hl_ns = vim.api.nvim_create_namespace("extra_lazy_changed_lines")
  local changed_bufs = {}
  local attached = {}

  local function is_file_buf(buf)
    -- ponytail: dashboard/lazy/etc use buftype=nofile; highlighting those
    -- paints the whole home screen green.
    return vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == ""
  end

  local function mark_changed(buf, first, new_last)
    if not is_file_buf(buf) then
      return
    end
    changed_bufs[buf] = changed_bufs[buf] or {}
    for l = first, new_last - 1 do
      if not changed_bufs[buf][l] then
        changed_bufs[buf][l] = true
        pcall(vim.api.nvim_buf_add_highlight, buf, changed_hl_ns, "DiffAdd", l, 0, -1)
      end
    end
  end

  local function attach_changed(buf)
    if attached[buf] or not is_file_buf(buf) then
      return
    end
    local ok = pcall(vim.api.nvim_buf_attach, buf, false, {
      on_lines = function(_, b, _, firstline, _, new_last, _)
        mark_changed(b, firstline, new_last)
      end,
      on_detach = function(_, b)
        attached[b] = nil
        changed_bufs[b] = nil
      end,
    })
    if ok then
      attached[buf] = true
    end
  end

  vim.api.nvim_create_autocmd({ "BufEnter", "BufReadPost", "BufNewFile" }, {
    group = augroup,
    pattern = "*",
    callback = function(args)
      if not is_file_buf(args.buf) then
        pcall(vim.api.nvim_buf_clear_namespace, args.buf, changed_hl_ns, 0, -1)
        return
      end
      attach_changed(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd("BufWritePost", {
    group = augroup,
    pattern = "*",
    callback = function(args)
      local buf = args.buf
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
    -- ponytail: feedkeys is async, so :normal! from visual would run per
    -- line; normal! <Esc> leaves visual synchronously (verified).
    if vim.fn.mode():match("[vV\22\19sS]") then
      vim.cmd("normal! " .. vim.api.nvim_replace_termcodes("<Esc>", true, false, true))
    end
  end

  local function save_err(err)
    local msg = tostring(err):gsub("^Vim:%w+:", ""):gsub("^%s+", "")
    vim.api.nvim_echo({ { "Error saving: " .. msg, "ErrorMsg" } }, false, {})
  end

  local function try_quit()
    local unsaved = false
    for _, info in ipairs(vim.fn.getbufinfo({ buflisted = 1, bufmodified = 1 })) do
      if info.loaded ~= 0 and vim.bo[info.bufnr].buftype == "" then
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
          -- ponytail: :wa fails on unnamed buffers (E141); don't quit then.
          local ok, err = pcall(vim.cmd, "wa")
          if ok then
            vim.cmd("qa")
          elseif err then
            save_err(err)
          end
        elseif choice == "Quit without Saving" then
          vim.cmd("qa!")
        end
      end
    )
  end

  local function open_cmdline()
    stop()
    -- ponytail: :normal! cannot enter the cmdline (verified no-op), feed the key instead.
    vim.api.nvim_feedkeys(":", "n", false)
  end

  -- Ctrl+S: Save file
  vim.keymap.set({ "n", "i", "v", "s" }, "<C-s>", function()
    -- ponytail: find("i") also matches "niI" (normal); check first char.
    if vim.fn.mode():sub(1, 1) == "i" then
      vim.cmd("stopinsert")
    end
    local ok, err = pcall(vim.cmd, "w")
    if ok then
      vim.api.nvim_echo({ { "Saved!", "String" } }, false, {})
    elseif err then
      save_err(err)
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
      vim.api.nvim_feedkeys("/", "n", false)
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
          -- ponytail: no match throws E486; stay silent like / does.
          pcall(vim.cmd, "normal! n")
        end
      end)
    end
  end, { desc = "Find Word Under Cursor" })

  -- Ctrl+D: Delete line (overrides scroll half-page)
  vim.keymap.set({ "n", "i" }, "<C-d>", function()
    stop()
    vim.cmd('normal! "_dd')
  end, { desc = "Delete Line" })

  -- Ctrl+G: Go to line (overrides LazyVim's git status)
  vim.keymap.set({ "n", "i", "v" }, "<C-g>", function()
    stop()
    vim.ui.input({ prompt = "Go to line: " }, function(input)
      local line = tonumber(input or "")
      if line and line > 0 then
        line = math.min(line, vim.api.nvim_buf_line_count(0))
        pcall(vim.api.nvim_win_set_cursor, 0, { line, 0 })
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
  -- ponytail: byte loop covers all of 33-126; space (32) is skipped so
  -- <leader> (space) keeps working (? and \ were silently missing before).
  for code = 33, 126 do
    local char = string.char(code)
    vim.keymap.set("n", char, "i" .. char, { noremap = true, desc = "" })
  end

  ----------------------------------------------------------------------
  -- 5. Visual Mode: typing replaces selection
  ----------------------------------------------------------------------
  for code = 32, 126 do
    local char = string.char(code)
    vim.keymap.set("v", char, '"_c' .. char, { noremap = true, desc = "" })
  end

  -- Visual mode Enter replaces selection with newline
  vim.keymap.set("v", "<CR>", '"_c<CR>', { noremap = true, desc = "" })
  vim.keymap.set("n", "<CR>", "i<CR>", { noremap = true, desc = "" })
  vim.keymap.set("n", "<BS>", '"_X', { desc = "Delete Character Backward" })
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
  vim.keymap.set("v", "<C-v>", '"_d"+P', { desc = "Paste" })
end

return M
