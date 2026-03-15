local M = {}

local function extract_query_params(text)
  local params = {}
  local seen = {}
  if not text then
    return params
  end

  for match in text:gmatch '(__:[%w_]+)' do
    if not seen[match] then
      table.insert(params, match)
      seen[match] = true
    end
  end
  return params
end

function M.generate_kulala_file_from_db()
  local db_name = 'dev_vpro_local'
  local target_dir = vim.fn.getcwd() .. '/api_requests/datatables'

  -- Using \a (unaligned), \t (tuples only/no headers), and explicitly setting the separator to |
  local query = [[
        \set QUIET 1
        \a
        \t
        \pset fieldsep '|'
        SELECT tag, dt_query FROM vpp_datatables_datatable ORDER BY tag ASC;
    ]]

  local db_url = nil
  local dbui_folder = vim.g.db_ui_save_location or (vim.fn.stdpath 'data' .. '/db_ui')
  local conn_file = vim.fn.expand(dbui_folder) .. '/connections.json'

  local f = io.open(conn_file, 'r')
  if f then
    local content = f:read '*a'
    f:close()

    local ok, conns = pcall(vim.fn.json_decode, content)
    if ok and type(conns) == 'table' then
      for _, conn in ipairs(conns) do
        if conn.name == db_name then
          db_url = conn.url
          break
        end
      end
    end
  end

  if not db_url then
    return vim.notify("Could not find URL for '" .. db_name .. "'", vim.log.levels.ERROR)
  end

  local has_lazy, lazy = pcall(require, 'lazy')
  if has_lazy then
    pcall(lazy.load, { plugins = { 'vim-dadbod' } })
  end

  local cmd_status, cmd = pcall(vim.fn['db#adapter#dispatch'], db_url, 'interactive')
  if not cmd_status then
    return vim.notify('Failed to generate command.', vim.log.levels.ERROR)
  end

  local exec_status, lines = pcall(vim.fn['db#systemlist'], cmd, query)
  if not exec_status then
    return vim.notify('Execution failed.', vim.log.levels.ERROR)
  end

  local tags = {}
  local current_entry = nil

  for _, line in ipairs(lines) do
    -- Fallback: explicitly ignore psql noise just in case \set QUIET 1 fails
    if line:match '^Tuples only is on' or line:match '^Output format is unaligned' or line:match '^Field separator is' or vim.trim(line) == '' then
      -- Skip this iteration entirely
    else
      -- Look for a tag at the very start of the line, immediately followed by a pipe
      -- E.g., "projects_issue_list|SELECT..."
      local tag_match, rest_of_line = line:match '^([%w_]+)|(.*)$'

      if tag_match then
        -- We found a new row! Start a fresh entry.
        current_entry = {
          tag = tag_match,
          query_text = rest_of_line .. '\n',
        }
        table.insert(tags, current_entry)
      elseif current_entry then
        -- This line doesn't have a tag, so it must be a continuation of the SQL query.
        -- We append it using the raw 'line' to preserve your SQL indentation!
        current_entry.query_text = current_entry.query_text .. line .. '\n'
      end
    end
  end

  if #tags == 0 then
    return vim.notify('Query returned 0 tags.', vim.log.levels.WARN)
  end

  vim.ui.select(tags, {
    prompt = 'Select Tag to Create .http File',
    format_item = function(item)
      -- This tells vim.ui.select what text to display in the UI list
      return item.tag
    end,
  }, function(choice)
    -- If the user hits Esc to abort, choice will be nil
    if not choice then
      return
    end

    -- Extract data from the selected table row
    local tag = choice.tag
    local dt_query = choice.query_text
    local params = extract_query_params(dt_query)

    local safe_filename = tag:gsub('[^%w%-_]', '_') .. '.http'
    local filepath = target_dir .. '/' .. safe_filename

    local function open_reusing_window(path)
      local target_full_path = vim.fn.fnamemodify(path, ':p')

      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        local buf_name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ':p')

        if buf_name == target_full_path then
          local tabpage = vim.api.nvim_win_get_tabpage(win)
          vim.api.nvim_set_current_tabpage(tabpage)
          vim.api.nvim_set_current_win(win)
          return
        end
      end

      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local buf = vim.api.nvim_win_get_buf(win)
        local name = vim.api.nvim_buf_get_name(buf)
        if name:match '%.http$' then
          vim.api.nvim_set_current_win(win)
          vim.cmd('edit ' .. path)
          return
        end
      end

      -- No .http window exists anywhere relevant. Open a new split.
      vim.cmd('vsplit ' .. path)
    end

    if vim.fn.filereadable(filepath) == 1 then
      vim.notify('Opening existing file: ' .. safe_filename, vim.log.levels.INFO)
      open_reusing_window(filepath)
      return
    end

    vim.fn.mkdir(target_dir, 'p')

    local file = io.open(filepath, 'w')
    if file then
      file:write('### Auto-generated request for ' .. tag .. '\n')
      file:write('GET {{BASE_URL}}/{{DATATABLE_API}}/' .. tag .. '/\n')

      if #params > 0 then
        for i, p in ipairs(params) do
          local prefix = (i == 1) and '?' or '&'
          file:write('\t' .. prefix .. p .. '=\n')
        end
      end

      file:write 'Accept: application/json\n'
      file:write 'Authorization: Bearer {{LOCAL_AUTH_TOKEN}}\n'
      file:close()

      vim.notify('Created new Kulala request: ' .. safe_filename, vim.log.levels.INFO)
      open_reusing_window(filepath)
    else
      vim.notify('Failed to create file.', vim.log.levels.ERROR)
    end
  end)
end

return M
