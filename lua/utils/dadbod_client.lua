local M = {}
local active_connection = nil

-- The Magic Bytes
local US = string.char(31) -- Unit Separator (replaces '|')
local RS = string.char(30) -- Record Separator (replaces '\n')

local function parse_delimited_text(raw_text, delimiter)
  local results = {}
  local records = vim.split(raw_text, RS, { trimempty = true })

  if #records == 0 then
    return results
  end

  for _, record in ipairs(records) do
    local clean_record = record:match '^%s*(.-)%s*$'
    -- Ignore dadbod (psql actually) noise
    if clean_record ~= '' and not clean_record:match '^Tuples Only' and not clean_record:match '^Output Format' then
      local columns = vim.split(clean_record, delimiter, { plain = true })
      table.insert(results, columns)
    end
  end

  return results
end

local function get_all_connections()
  local dbui_folder = vim.g.db_ui_save_location or (vim.fn.stdpath 'data' .. '/db_ui')
  local conn_file = vim.fn.expand(dbui_folder) .. '/connections.json'

  local f = io.open(conn_file, 'r')
  if not f then
    return {}
  end

  local content = f:read '*a'
  f:close()

  local ok, conns = pcall(vim.fn.json_decode, content)
  if ok and type(conns) == 'table' then
    return conns
  end
end

function M.select_database(callback)
  local conns = get_all_connections()

  if #conns == 0 then
    vim.notify('No databases found in Dadbod UI Connections.json', vim.log.levels.WARN)
  end

  vim.ui.select(conns, {
    prompt = 'Select Active Database for Session',
    format_item = function(item)
      return item.name
    end,
  }, function(choice)
    if not choice then
      return
    end

    active_connection = choice
    vim.notify('Active DB set to : ' .. active_connection.name, vim.log.levels.INFO)
    if callback then
      callback(active_connection)
    end
  end)
end

function M.with_connection(callback)
  if active_connection then
    callback(active_connection)
  else
    M.select_database(callback)
  end
end

function M.query(sql_query, on_success)
  M.with_connection(function(conn)
    local cmd_status, cmd = pcall(vim.fn['db#adapter#dispatch'], conn.url, 'interactive')

    if not cmd_status then
      vim.notify('Failed to generate db command for ' .. conn.name, vim.log.levels.ERROR)
      return
    end

    vim.system(cmd, {
      stdin = sql_query,
      text = true,
    }, function(out)
      if out.code ~= 0 then
        vim.schedule(function()
          vim.notify('DB Error: ' .. (out.stderr or 'Unknown'), vim.log.levels.ERROR)
        end)
        return
      end

      local parsed_data = parse_delimited_text(out.stdout, US)
      vim.schedule(function()
        if on_success then
          on_success(parsed_data)
        end
      end)
    end)
  end)
end

return M
