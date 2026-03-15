local M = {}

local US = string.char(31) -- Unit Separator (replaces '|')
local RS = string.char(30) -- Record Separator (replaces '\n')

local db = require 'utils.dadbod_client'

local sql_template = string.format(
  [[
  \set QUIET 1
  \a \t 
  \pset fieldsep '%s'
  \pset recordsep '%s'

  SELECT 
    api_tag, structure
  FROM
    vpp_masterdata_apiprocessorstructure
  WHERE
    structure::text ilike '%%%%%%s%%%%'
]],
  US,
  RS
)
function M.search_apiprocessorstructures()
  vim.ui.input({ prompt = 'Search inside ApiProcessorStructure: ' }, function(input)
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

        vim.ui.select(data, {
          prompt = 'Select an API processor structure to view',
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
          vim.bo[buf].filetype = 'json'

          local raw_json = choice[2] or '{}'
          local lines = vim.split(raw_json, '\n', { plain = true })

          vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

          if vim.fn.executable 'jq' == 1 then
            vim.cmd '%!jq .'
          end

          local msg = string.format('Opened %s', choice[1])
          vim.notify(msg, vim.log.levels.INFO)
        end)
      end)
    )
  end)
end

return M
