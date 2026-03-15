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

M.search_apiprocessorstructures = db_pickers.static_db_picker(
  [[
      SELECT api_tag, structure FROM vpp_masterdata_apiprocessorstructure
  ]],

  {
    title = 'Live Api Processor Structures Search',
    display_column = 1,
    preview_column = 2,
    filetype = 'json',
  }
)

M.grep_apiprocessorstructures = db_pickers.dynamic_db_picker {
  title = 'Live DT_QUERY Search',
  debounce = 300,
  query_template = [[
  SELECT api_tag, structure FROM vpp_masterdata_apiprocessorstructure WHERE structure::text ilike '%%%s%%'
  ]],
  display_column = 1,
  preview_column = 2,
  filetype = 'json',
}

M.search_datatable_tags = db_pickers.static_db_picker(
  [[
      SELECT tag, dt_query FROM vpp_datatables_datatable
  ]],

  {
    title = 'Live DT_QUERY Search',
    display_column = 1,
    preview_column = 2,
    filetype = 'sql',
  }
)

M.grep_datatables_dynamic = db_pickers.dynamic_db_picker {
  title = 'Live DT_QUERY Search',
  debounce = 300,
  query_template = [[
  SELECT tag, dt_query FROM vpp_datatables_datatable WHERE dt_query::text ilike '%%%s%%']],
  display_column = 1,
  preview_column = 2,
  filetype = 'sql',
}

return M
