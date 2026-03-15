local M = {}

local db_pickers = require 'utils.database_pickers'

M.grep_datatables = db_pickers.create_telescope_workflow {
  title = 'DT QUERY GREP',
  prompt_text = 'Search DT QUERY: ',
  filetype = 'sql',
  display_index = 1,
  data_index = 2,
  build_query = function(input, us_byte, rs_byte)
    -- vim.print(input, us_byte, rs_byte)
    -- debug.debug()
    return string.format(
      [[
     \set QUIET 1
     \a \t \pset fieldsep '%s' \pset recordsep '%s'
     SELECT tag, dt_query FROM vpp_datatables_datatable
     WHERE dt_query::text ilike '%%%s%%'
    ]],
      us_byte,
      rs_byte,
      input
    )
  end,
}

M.grep_datatables_dynamic = db_pickers.dynamic_db_picker {
  title = 'Live DT_QUERY Search',
  debounce = 300,
  -- The %s is where your telescope prompt goes!
  query_template = [[
  SELECT tag, dt_query FROM vpp_datatables_datatable WHERE dt_query::text ilike '%%%s%%']],
  display_column = 1, -- or 'tag' if your DB driver returns keys
  preview_column = 2, -- or 'dt_query'
  filetype = 'sql',
}

return M
