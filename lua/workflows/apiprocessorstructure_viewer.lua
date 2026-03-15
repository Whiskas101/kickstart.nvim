local M = {}

local db = require 'utils.dadbod_client'

local sql = [[
  \set QUIET 1
  \a \t \pset fieldsep '|'
  SELECT api_tag, structure FROM vpp_masterdata_apiprocessorstructure
]]

function M.get_apiprocessorstructures()
  db.query(sql, function(data)
    vim.ui.select(data, {
      prompt = 'Select an API Processor Structure to view',
      format_item = function(row)
        return row[1] -- the api_tag value
      end,
    }, function(choice)
      if not choice then
        return
      end

      -- open a new buffer to show the data in
      vim.cmd 'vnew'
      local buf = vim.api.nvim_get_current_buf()
      vim.bo[buf].buftype = 'nofile'
      vim.bo[buf].bufhidden = 'wipe'
      vim.bo[buf].swapfile = false
      vim.bo[buf].filetype = 'json'

      local lines = vim.split(choice[2], '\n', { plain = true })

      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

      if vim.fn.executable 'jq' == 1 then
        vim.cmd '%!jq .'
      end

      -- vim.fn.setreg('+', choice[2])

      local msg = string.format('Opened %s', choice[1])
      vim.notify(msg)
    end)
  end)
end

return M
