local M = {}

local db = require 'utils.dadbod_client'

local US = string.char(31) -- Unit Separator (replaces '|')
local RS = string.char(30) -- Record Separator (replaces '\n')

local sql_template = string.format(
  [[
  \set QUIET 1
  \a \t
  \pset fieldsep '%s'
  \pset recordsep '%s'
  SELECT tag, dt_query 
  FROM vpp_datatables_datatable
  WHERE dt_query::text ilike '%%%%%%s%%%%' 
]],
  US,
  RS
)

function M.grep_datatables()
  vim.ui.input({ prompt = 'Search inside vpp_datatables_datatable: ' }, function(input)
    if not input or input == '' then
      vim.notify('Search cancelled', vim.log.levels.INFO)
      return
    end

    local safe_input = input:gsub("'", "''")
    local query = string.format(sql_template, safe_input)

    db.query(
      query,
      vim.schedule_wrap(function(data)
        if not data or type(data) ~= 'table' or #data == 0 then
          return
        end

        -- vim.print(data)

        vim.ui.select(data, {
          prompt = 'Select a DT QUERY to view',
          format_item = function(row)
            if type(row) ~= 'table' then
              return 'ERROR: row is not a table'
            end
            return row[1] or 'UNKNOWN_TAG'
          end,
        }, function(choice)
          if not choice then
            return
          end

          vim.cmd 'vnew'
          local buf = vim.api.nvim_get_current_buf()
          vim.bo[buf].buftype = 'nofile'
          vim.bo[buf].bufhidden = 'wipe'
          vim.bo[buf].swapfile = false
          vim.bo[buf].filetype = 'sql'

          local dt_query = choice[2] or '{}'
          local lines = vim.split(dt_query, '\n', { plain = true })

          vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

          -- if vim.fn.executable 'jq' == 1 then
          --   vim.cmd '%!jq .'
          -- end

          local msg = string.format('Opened %s', choice[1])
          vim.notify(msg, vim.log.levels.INFO)
        end)
      end)
    )
  end)
end

return M
