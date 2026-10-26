-- extra-lazy.nvim: Enhanced editor mode for LazyVim
-- Inspired by ox (github.com/curlpipe/ox) and novim (github.com/link2004/novim)
-- Key features: Ctrl+S save, Ctrl+Q quit, type-to-edit, mouse-driven operation

local M = {}
local has_setup = false
local hint_text = nil
local attached = {}
local generation = 0

-- Defined at require time so a statusline can call it before setup().
---@diagnostic disable-next-line: lowercase-global
function _G.extra_lazy_hints()
  if not hint_text then
    return ""
  end
  local mode = vim.fn.mode()
  if mode == "v" or mode == "V" or mode == "\22" then
    return hint_text.visual
  elseif vim.bo.modified then
    return hint_text.modified
  else
    return hint_text.normal
  end
end

function M.setup(opts)
  if has_setup then
    return
  end

  opts = vim.tbl_deep_extend("force", {
    options = {
      mouse = "a",
      mousemodel = "extend",
      clipboard = "unnamedplus",
      showmode = false,
      virtualedit = "onemore",
    },
    mouse_double_click = true,
    changed_lines = "DiffAdd",
    hints = {
      visual = "^C Copy  ^X Cut  ^A All",
      modified = "^S Save  ^Z Undo  ^Q Quit",
      normal = "^V Paste  ^A All  ^Q Quit",
    },
    type_to_insert = true,
    visual_replace = true,
    arrow_selection = true,
    word_movement = true,
    keymaps = {},
  }, opts or {})

  generation = generation + 1
  local gen = generation

  -- A remapped lhs that you can type must not shadow Insert/Select typing.
  local function typing_modes(modes)
    if type(modes) ~= "table" then
      return (modes == "n" or modes == "v") and modes or false
    end
    local out = {}
    for _, mode in ipairs(modes) do
      if mode == "n" or mode == "v" then
        out[#out + 1] = mode
      end
    end
    return #out > 0 and out or false
  end

  local overrides = {}
  local function map(modes, lhs, rhs, options)
    if opts.keymaps == false or opts.keymaps[lhs] == false then
      return
    end
    local key = opts.keymaps[lhs]
    if key and overrides then
      -- ponytail: remapped keymaps must win over type-to-insert loops, so
      -- they're applied after all default mappings are set.
      -- "<leader>w" and "j" are typed in Insert mode, so remaps to them stay
      -- Normal/Visual only instead of swallowing typed text.
      local target_modes = key:gsub("<[^>]+>", "") ~= "" and typing_modes(modes) or modes
      if target_modes then
        overrides[#overrides + 1] = { target_modes, key, rhs, options }
      end
    else
      vim.keymap.set(modes, key or lhs, rhs, options)
    end
  end
  ----------------------------------------------------------------------
  -- 1. Display & Editor Options
  ----------------------------------------------------------------------
  for name, value in pairs(opts.options or {}) do
    vim.opt[name] = value
  end

  ----------------------------------------------------------------------
  -- 2. Autocommands
  ----------------------------------------------------------------------
  local augroup = vim.api.nvim_create_augroup("extra_lazy", { clear = true })

  -- Mouse double-click opens file/folder under cursor in netrw
  if opts.mouse_double_click then
    vim.api.nvim_create_autocmd("FileType", {
      group = augroup,
      pattern = "netrw",
      callback = function()
        map("n", "<2-LeftMouse>", "<CR>", { buffer = true, silent = true })
      end,
    })
  end

  -- Track changed lines with green highlights (like ox/novim)
  -- ponytail: on_lines gives the exact edited range; cursor-line-only
  -- marking missed multi-line pastes.
  local changed_hl_ns = vim.api.nvim_create_namespace("extra_lazy_changed_lines")

  local function is_file_buf(buf)
    -- ponytail: dashboard/lazy/etc use buftype=nofile; highlighting those
    -- paints the whole home screen green.
    return vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == ""
  end

  local function mark_changed(buf, first, new_last)
    if not is_file_buf(buf) then
      return
    end
    -- ponytail: changed_lines=true means default group; raw true is not a hl group.
    local hl = opts.changed_lines == true and "DiffAdd" or opts.changed_lines
    if new_last <= first then
      -- A deletion has no new text; mark the line the text was joined into.
      local count = vim.api.nvim_buf_line_count(buf)
      first = math.min(first, count - 1)
      new_last = math.min(first + 1, count)
    end
    -- One query for the whole range, not one per line: big pastes are common.
    local marked = {}
    local marks = vim.api.nvim_buf_get_extmarks(buf, changed_hl_ns, { first, 0 }, { new_last - 1, -1 }, {})
    for _, mark in ipairs(marks) do
      marked[mark[2]] = true
    end
    for l = first, new_last - 1 do
      -- Ask the namespace, not a line-number table: extmarks move with edits.
      -- right_gravity=false keeps the mark on its line when the line is replaced.
      if not marked[l] then
        pcall(vim.api.nvim_buf_set_extmark, buf, changed_hl_ns, l, 0, {
          line_hl_group = hl,
          right_gravity = false,
        })
      end
    end
  end

  local function attach_changed(buf)
    if attached[buf] or not is_file_buf(buf) then
      return
    end
    local ok = pcall(vim.api.nvim_buf_attach, buf, false, {
      on_lines = function(_, b, _, firstline, _, new_last, _)
        -- A callback from a previous setup() stays attached after _reset().
        if gen ~= generation then
          return true
        end
        mark_changed(b, firstline, new_last)
      end,
      on_detach = function(_, b)
        if attached[b] == gen then
          attached[b] = nil
        end
      end,
    })
    if ok then
      attached[buf] = gen
    end
  end

  if opts.changed_lines then
    local function clear_changed(buf)
      pcall(vim.api.nvim_buf_clear_namespace, buf, changed_hl_ns, 0, -1)
    end

    vim.api.nvim_create_autocmd({ "BufEnter", "BufReadPost", "BufNewFile" }, {
      group = augroup,
      pattern = "*",
      callback = function(args)
        if not is_file_buf(args.buf) then
          clear_changed(args.buf)
          return
        end
        attach_changed(args.buf)
        -- Reloads and undos done in another buffer leave 'modified' false but
        -- stale marks behind.
        if not vim.bo[args.buf].modified then
          clear_changed(args.buf)
        end
      end,
    })

    vim.api.nvim_create_autocmd("BufWritePost", {
      group = augroup,
      pattern = "*",
      callback = function(args)
        clear_changed(args.buf)
      end,
    })

    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
      group = augroup,
      pattern = "*",
      callback = function(args)
        -- ponytail: Neovim has no undo event; 'modified' clears when undo
        -- returns to the saved state, which is when the marks should go.
        if not vim.bo[args.buf].modified then
          clear_changed(args.buf)
        end
      end,
    })

    -- ponytail: setup runs after buffers already exist; attach those too.
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      attach_changed(buf)
    end
  end

  -- Dynamic hints for statusline
  hint_text = opts.hints or nil

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
    local msg = tostring(err):gsub("^.*Vim%(?[%w_]*%)?:%s*", ""):match("^[^\n]*") or ""
    vim.api.nvim_echo({ { "Error saving: " .. msg, "ErrorMsg" } }, false, {})
  end

  local function report(ok, err)
    if ok then
      vim.api.nvim_echo({ { "Saved!", "String" } }, false, {})
    elseif err then
      save_err(err)
    end
  end

  -- Expand ~ and $VAR from a prompt, but keep #, %, and wildcards literal:
  -- expand() would otherwise target the alternate file or many files at once.
  local function expand_path(input)
    local escaped = input:gsub("[\\%%#%*%?%[%{]", "\\%0")
    return vim.fn.expand(escaped)
  end

  local function write(buf, target)
    local function run(cmd)
      if not vim.api.nvim_buf_is_valid(buf) then
        report(false, "buffer was closed")
        return
      end
      local ok, err
      -- Catch inside the callback so nvim_buf_call doesn't wrap the error
      -- in a Lua traceback.
      local called, call_err = pcall(vim.api.nvim_buf_call, buf, function()
        ok, err = pcall(vim.api.nvim_cmd, cmd, {})
      end)
      if not called then
        ok, err = false, call_err
      end
      report(ok, err)
    end
    if target then
      -- ponytail: fnameescape keeps %, # and spaces literal in Ex arguments;
      -- saveas! overwrites the name the user picked.
      run({ cmd = "saveas", args = { vim.fn.fnameescape(target) }, bang = true, mods = {} })
    else
      run({ cmd = "write", args = {}, mods = {} })
    end
  end

  local function save()
    local buf = vim.api.nvim_get_current_buf()
    -- ponytail: :w fails with E32 on unnamed buffers; ask for a name instead.
    if vim.bo[buf].buftype == "" and vim.api.nvim_buf_get_name(buf) == "" then
      vim.ui.input({ prompt = "Save as: ", completion = "file" }, function(input)
        if not (input and input:match("%S")) then
          return
        end
        -- Check and write the same expanded path, like :saveas does.
        local target = expand_path(input)
        local kind = vim.fn.getftype(target)
        if kind == "dir" then
          vim.api.nvim_echo({ { target .. " is a directory", "ErrorMsg" } }, false, {})
          return
        end
        -- getftype, not filereadable: an existing file you cannot read still
        -- needs the overwrite question.
        if kind ~= "" then
          vim.ui.select({ "Overwrite", "Cancel" }, { prompt = target .. " exists:" }, function(choice)
            if choice == "Overwrite" then
              write(buf, target)
            end
          end)
        else
          write(buf, target)
        end
      end)
    else
      write(buf, nil)
    end
  end

  -- No buflisted filter: :qall also refuses unlisted modified buffers.
  local function modified_bufs()
    local bufs = {}
    for _, info in ipairs(vim.fn.getbufinfo({ bufmodified = 1 })) do
      if info.loaded ~= 0 and vim.bo[info.bufnr].buftype == "" then
        bufs[#bufs + 1] = info.bufnr
      end
    end
    return bufs
  end

  local function try_quit()
    local unsaved = modified_bufs()
    if #unsaved == 0 then
      vim.cmd("qa")
      return
    end
    vim.ui.select(
      { "Save and Quit", "Quit without Saving", "Cancel" },
      { prompt = "You have unsaved changes:" },
      function(choice)
        if choice == "Save and Quit" then
          -- ponytail: :wa fails on unnamed buffers (E141); ask for a name first.
          for _, buf in ipairs(unsaved) do
            if vim.api.nvim_buf_get_name(buf) == "" then
              vim.api.nvim_echo({ { "Save the unnamed buffer first (Ctrl+S)", "WarningMsg" } }, false, {})
              return
            end
          end
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
  map({ "n", "i", "v", "s" }, "<C-s>", function()
    -- ponytail: find("i") also matches "niI" (normal); check first char.
    if vim.fn.mode():sub(1, 1) == "i" then
      vim.cmd("stopinsert")
    end
    save()
  end, { desc = "Save File" })

  -- Ctrl+Q: Quit
  map({ "n", "i", "v" }, "<C-q>", try_quit, { desc = "Quit" })

  -- Ctrl+N: New file
  map({ "n", "i", "v" }, "<C-n>", function()
    stop()
    vim.cmd("enew")
  end, { desc = "New File" })

  -- Ctrl+O: Open file
  map({ "n", "i", "v" }, "<C-o>", function()
    stop()
    vim.ui.input({ prompt = "Open file: " }, function(input)
      if input and input ~= "" then
        vim.cmd.e({ args = { vim.fn.fnameescape(expand_path(input)) } })
      end
    end)
  end, { desc = "Open File" })

  -- Ctrl+Z: Undo (overrides terminal suspend)
  map({ "n", "i", "v" }, "<C-z>", function()
    stop()
    vim.cmd("undo")
  end, { desc = "Undo" })

  -- Ctrl+Y: Redo
  map({ "n", "i", "v" }, "<C-y>", function()
    stop()
    vim.cmd("redo")
  end, { desc = "Redo" })

  -- Ctrl+A: Select all
  map({ "n", "i", "v" }, "<C-a>", function()
    stop()
    vim.cmd("normal! ggVG")
  end, { desc = "Select All" })

  -- Ctrl+F: Search with Telescope
  map({ "n", "i", "v" }, "<C-f>", function()
    stop()
    local ok = pcall(function()
      require("telescope.builtin").live_grep()
    end)
    if not ok then
      vim.api.nvim_feedkeys("/", "n", false)
    end
  end, { desc = "Find in Files" })

  -- Ctrl+R: Find word under cursor
  map({ "n", "i", "v" }, "<C-r>", function()
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
  map({ "n", "i" }, "<C-d>", function()
    stop()
    vim.cmd('normal! "_dd')
  end, { desc = "Delete Line" })
  map("v", "<C-d>", '"_d', { desc = "Delete Selection" })

  -- Ctrl+G: Go to line (overrides LazyVim's git status)
  map({ "n", "i", "v" }, "<C-g>", function()
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
  map({ "n", "i" }, "<C-k>", open_cmdline, { desc = "Command Line" })

  -- ponytail: LazyVim overrides <C-k> on VeryLazy, so we re-map there too.
  -- Our autocmd is registered during plugin config (before VeryLazy fires
  -- in normal startup), so our callback runs after LazyVim's.
  vim.api.nvim_create_autocmd("User", {
    pattern = "VeryLazy",
    group = augroup,
    callback = function()
      map({ "n", "i" }, "<C-k>", open_cmdline, { desc = "Command Line" })
    end,
  })

  -- Double-Esc: Quit (novim-style)
  map("n", "<Esc><Esc>", try_quit, { desc = "Quit (double Esc)" })

  ----------------------------------------------------------------------
  -- 4. Type-to-Insert Mode
  ----------------------------------------------------------------------
  -- ponytail: help, quickfix, netrw and the dashboard are not editable;
  -- there a printable key must keep its normal meaning. Expr mappings keep
  -- the returned keys in the mode the callback was started from.
  -- 33-126 skips space so <leader> (space) still works.
  local function editable()
    local buf = vim.api.nvim_get_current_buf()
    return is_file_buf(buf) and vim.bo[buf].modifiable
  end

  if opts.type_to_insert then
    vim.api.nvim_create_autocmd("VimEnter", {
      group = augroup,
      callback = function()
        if is_file_buf(vim.api.nvim_get_current_buf()) then
          pcall(vim.cmd, "startinsert")
        end
      end,
    })
    for code = 33, 126 do
      local char = string.char(code)
      map("n", char, function()
        return editable() and "i" .. char or char
      end, { expr = true, noremap = true, desc = "" })
    end
    map("n", "<CR>", function()
      return editable() and "i<CR>" or "<CR>"
    end, { expr = true, noremap = true, desc = "" })
    map("n", "<BS>", function()
      return editable() and '"_X' or "<BS>"
    end, { expr = true, desc = "Delete Character Backward" })
  end

  ----------------------------------------------------------------------
  -- 5. Visual Mode: typing replaces selection
  ----------------------------------------------------------------------
  if opts.visual_replace then
    for code = 32, 126 do
      local char = string.char(code)
      map("v", char, function()
        return editable() and '"_c' .. char or char
      end, { expr = true, noremap = true, desc = "" })
    end

    -- Visual mode Enter replaces selection with newline
    map("v", "<CR>", function()
      return editable() and '"_c<CR>' or "<CR>"
    end, { expr = true, noremap = true, desc = "" })
    map("v", "<BS>", function()
      return editable() and '"_d' or "<BS>"
    end, { expr = true, desc = "Delete Selection" })
    map("v", "<Del>", function()
      return editable() and '"_d' or "<Del>"
    end, { expr = true, desc = "Delete Selection" })
  end

  ----------------------------------------------------------------------
  -- 6. Arrow-key Selection
  ----------------------------------------------------------------------
  if opts.arrow_selection then
    for _, dir in ipairs({ { "Left", "h" }, { "Right", "l" }, { "Up", "k" }, { "Down", "j" } }) do
      map("n", "<S-" .. dir[1] .. ">", "v" .. dir[2], { desc = "Select " .. dir[1] })
      map("i", "<S-" .. dir[1] .. ">", "<Esc>v" .. dir[2], { desc = "Select " .. dir[1] })
      map("v", "<S-" .. dir[1] .. ">", dir[2], { desc = "Extend Selection " .. dir[1] })
    end
  end

  ----------------------------------------------------------------------
  -- 7. Word-wise Movement and Deletion
  ----------------------------------------------------------------------
  if opts.word_movement then
    -- ponytail: native word motions; <C-o> keeps insert mode.
    for _, dir in ipairs({ { "Left", "b" }, { "Right", "w" } }) do
      map("n", "<C-" .. dir[1] .. ">", dir[2], { desc = "Move " .. dir[1] .. " by Word" })
      map("i", "<C-" .. dir[1] .. ">", "<C-o>" .. dir[2], { desc = "Move " .. dir[1] .. " by Word" })
      map("v", "<C-" .. dir[1] .. ">", dir[2], { desc = "Select " .. dir[1] .. " by Word" })
    end
    -- ponytail: "_ keeps registers clean, like <BS> -> "_X above.
    map("n", "<C-BS>", '"_db', { desc = "Delete Word Backward" })
    map("i", "<C-BS>", '<C-o>"_db', { desc = "Delete Word Backward" })
    map("v", "<C-BS>", '"_d', { desc = "Delete Selection" })
    map("n", "<C-Del>", '"_dw', { desc = "Delete Word Forward" })
    map("i", "<C-Del>", '<C-o>"_dw', { desc = "Delete Word Forward" })
    map("v", "<C-Del>", '"_d', { desc = "Delete Selection" })
  end

  ----------------------------------------------------------------------
  -- 8. Clipboard Operations
  ----------------------------------------------------------------------
  map("v", "<C-c>", '"+ygv', { desc = "Copy" })
  map("v", "<C-x>", '"+x', { desc = "Cut" })
  map("n", "<C-v>", '"+gP', { desc = "Paste" })
  map("i", "<C-v>", '<C-r>+', { desc = "Paste" })
  map("v", "<C-v>", '"_d"+P', { desc = "Paste" })

  for _, mapping in ipairs(overrides) do
    vim.keymap.set(unpack(mapping))
  end
  overrides = nil
  has_setup = true
end

-- ponytail: dev reload keeps module cache, so setup() would no-op
function M._reset()
  generation = generation + 1
  attached = {}
  has_setup = false
  hint_text = nil
end

return M
