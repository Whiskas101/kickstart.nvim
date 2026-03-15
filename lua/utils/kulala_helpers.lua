local M = {}
local json = require 'kulala.utils.json'

function M.get_json_payload(obj)
  local function dlog(msg)
    local safe_msg = 'DEBUG: ' .. tostring(msg)
    if client and type(client.log) == 'function' then
      client.log(safe_msg)
    else
      print('KULALA ' .. safe_msg)
    end
  end

  dlog 'Entering get_json_payload'

  if type(obj) == 'nil' then
    dlog 'FAIL: The passed object (request/response) is nil.'
    return nil
  end

  if type(obj.body) == 'nil' then
    dlog 'FAIL: obj.body is nil.'
    return nil
  end

  dlog('obj.body type: ' .. type(obj.body))

  if type(obj.body) == 'table' then
    dlog 'SUCCESS: obj.body is already a table. Returning directly.'
    return obj.body
  end

  local b = obj.body
  local content = b

  if type(b) == 'string' then
    dlog('Raw string length: ' .. #b)

    local preview = b:sub(1, 60):gsub('\n', '\\n'):gsub('\r', '\\r')
    dlog('String preview: ' .. preview)

    if b:match 'The size of response is > 32Kb' then
      dlog "Matched '> 32Kb' condition."
      local path = b:match 'Path to response:%s*([^\r\n]+)'
      dlog('Extracted raw path: ' .. tostring(path))

      if path then
        path = path:gsub('%s+$', '')
        path = path:gsub('/', '\\')
        dlog('Normalized Windows path: ' .. path)

        local is_readable = vim.fn.filereadable(path)
        dlog('vim.fn.filereadable check: ' .. tostring(is_readable))

        if is_readable == 0 then
          dlog 'FAIL: File does not exist or lacks read permissions.'
          return nil
        end

        local ok, lines = pcall(vim.fn.readfile, path)
        if not ok then
          dlog('FAIL: readfile crashed. Error: ' .. tostring(lines))
          return nil
        end

        content = table.concat(lines, '')
        dlog('Successfully read large file. Content length: ' .. #content)
      else
        dlog 'FAIL: Regex failed to extract path from string.'
      end
    elseif b:match '^<' then
      dlog "Matched '<' (Request syntax)."
      local path = b:gsub('^<%s+', '')
      local absolute_path = vim.fn.fnamemodify(path, ':p')
      dlog('Absolute request path: ' .. absolute_path)

      local ok, lines = pcall(vim.fn.readfile, absolute_path)
      if not ok then
        dlog 'FAIL: Could not read request file.'
        return nil
      end
      content = table.concat(lines, '')
      dlog('Successfully read request file. Content length: ' .. #content)
    end
  end

  if type(content) == 'string' and content ~= '' then
    dlog('Attempting JSON parse. Target length: ' .. #content)
    local ok, data = pcall(json.parse, content)
    if not ok then
      dlog('FAIL: JSON parse crashed. Error: ' .. tostring(data))
      return nil
    end
    dlog 'SUCCESS: JSON parsed successfully.'
    return data
  end

  dlog('FAIL: Reached end without returning. Content type is: ' .. type(content))
  return nil
end

return M
