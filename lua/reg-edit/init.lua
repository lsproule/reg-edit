local M = {}
local CTRL_V = string.char(22)
local READ_ONLY_REGISTERS = {
  [":"] = true,
  ["."] = true,
  ["%"] = true,
  ["#"] = true,
}

local function parse_register_line(line)
  local reg_type, reg_name, content = line:match('^%s*(%S)%s+"(.)%s%s%s(.*)$')
  if not reg_type or not reg_name then
    reg_type, reg_name, content = line:match('^%s*(%S)%s+"(.)%s+(.*)$')
  end
  if not reg_type or not reg_name then
    return nil
  end

  return {
    reg_type = reg_type,
    reg_name = reg_name,
    content = content or "",
  }
end

local function format_register_line(reg_type, reg_name, content)
  return string.format('  %s  "%s   %s', reg_type, reg_name, content or "")
end

local function extract_content_from_line(line, prefix)
  if prefix and line:sub(1, #prefix) == prefix then
    return line:sub(#prefix + 1)
  end

  local content = line:match('^%s*%S%s+"."%s%s%s(.*)$')
  if content ~= nil then
    return content
  end

  content = line:match('^%s*%S%s+"."%s+(.*)$')
  if content ~= nil then
    return content
  end

  return ""
end

local function to_setreg_type(reg_type)
  if reg_type == "l" then
    return "V"
  end
  if reg_type == "b" then
    return CTRL_V
  end
  return "v"
end

local function encode_register_content(content)
  local encoded = content or ""

  encoded = encoded:gsub("%^([A-Z%[\\%]%^_?])", function(ctrl)
    if ctrl == "?" then
      return string.char(127)
    end

    local byte = string.byte(ctrl)
    if byte >= string.byte("A") and byte <= string.byte("Z") then
      return string.char(byte - 64)
    end

    if ctrl == "[" then
      return string.char(27)
    end
    if ctrl == "\\" then
      return string.char(28)
    end
    if ctrl == "]" then
      return string.char(29)
    end
    if ctrl == "^" then
      return string.char(30)
    end
    if ctrl == "_" then
      return string.char(31)
    end

    return "^" .. ctrl
  end)

  return encoded
end

local function is_writable_register(reg_name)
  if type(reg_name) ~= "string" or #reg_name ~= 1 then
    return false
  end

  if READ_ONLY_REGISTERS[reg_name] then
    return false
  end

  return reg_name:match('^[0-9a-zA-Z"*+/_%-]$') ~= nil
end

M.create_temp_buffer = function()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype", "acwrite", { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
  vim.api.nvim_set_option_value("filetype", "regedit", { buf = buf })
  vim.api.nvim_buf_set_name(buf, "RegEdit")
  return buf
end

M.create_temp_window = function(buf)
  vim.cmd.tabnew()
  local win = vim.api.nvim_get_current_win()
  local empty_buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_win_set_buf(win, buf)
  if empty_buf ~= buf and vim.api.nvim_buf_is_valid(empty_buf) then
    vim.api.nvim_buf_delete(empty_buf, { force = true })
  end
  return win
end

M.load_register_output = function(buf)
  local output = vim.api.nvim_exec2("registers", { output = true }).output
  local lines = vim.split(output, "\n", { plain = true })
  local line_map = {}

  for idx, line in ipairs(lines) do
    local parsed = parse_register_line(line)
    if parsed then
      line_map[tostring(idx)] = {
        reg_type = parsed.reg_type,
        reg_name = parsed.reg_name,
        prefix = format_register_line(parsed.reg_type, parsed.reg_name, ""),
      }
    end
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_var(buf, "regedit_line_map", line_map)
  vim.api.nvim_buf_set_var(buf, "regedit_original_lines", lines)
end

M.clear_buffer_entries = function(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  for idx, line in ipairs(lines) do
    local parsed = parse_register_line(line)
    if parsed then
      lines[idx] = format_register_line(parsed.reg_type, parsed.reg_name, "")
    end
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
end

M.sync_unnamed_from_yank = function()
  vim.fn.setreg("\"", vim.fn.getreg("0"), vim.fn.getregtype("0"))
end

M.write_buffer_to_registers = function(buf, sync_unnamed)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local ok, line_map = pcall(vim.api.nvim_buf_get_var, buf, "regedit_line_map")
  if not ok then
    line_map = {}
  end
  local ok2, original_lines = pcall(vim.api.nvim_buf_get_var, buf, "regedit_original_lines")
  if not ok2 then
    original_lines = {}
  end

  local unnamed_entry = nil
  local unnamed_modified = false

  for idx, line in ipairs(lines) do
    local mapped = line_map[tostring(idx)]
    if mapped and is_writable_register(mapped.reg_name) then
      if mapped.reg_name == "\"" then
        unnamed_entry = { line = line, mapped = mapped }
        unnamed_modified = line ~= original_lines[idx]
      else
        vim.fn.setreg(
          mapped.reg_name,
          encode_register_content(extract_content_from_line(line, mapped.prefix)),
          to_setreg_type(mapped.reg_type)
        )
      end
    end
  end

  if unnamed_modified and unnamed_entry then
    vim.fn.setreg(
      "\"",
      encode_register_content(extract_content_from_line(unnamed_entry.line, unnamed_entry.mapped.prefix)),
      to_setreg_type(unnamed_entry.mapped.reg_type)
    )
  elseif sync_unnamed then
    M.sync_unnamed_from_yank()
  end

  vim.api.nvim_set_option_value("modified", false, { buf = buf })

  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
end

M.setup = function(opts)
  opts = opts or {}
  local command_name = opts.command_name or "RegEdit"
  local keys = opts.keys or {}
  local open_map = keys.open
  if open_map == nil then
    open_map = "<leader>re"
  end
  local clear_map = keys.clear or ((opts.prefix or "<leader>") .. "c")
  local sync_unnamed = opts.sync_unnamed
  if sync_unnamed == nil then
    sync_unnamed = true
  end

  vim.api.nvim_create_user_command(command_name, function()
    local buf = M.create_temp_buffer()
    M.load_register_output(buf)
    M.create_temp_window(buf)

    vim.keymap.set("n", clear_map, function()
      M.clear_buffer_entries(buf)
    end, {
      buffer = buf,
      silent = true,
      desc = "Clear register entries",
    })

    vim.api.nvim_create_autocmd("BufWriteCmd", {
      buffer = buf,
      callback = function()
        M.write_buffer_to_registers(buf, sync_unnamed)
      end,
    })
  end, { force = true })

  if open_map then
    vim.keymap.set("n", open_map, "<cmd>" .. command_name .. "<CR>", {
      silent = true,
      desc = "Open register editor",
    })
  end
end

return M
