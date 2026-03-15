local M = {}

local db = require 'utils.dadbod_client'
local pickers = require 'telescope.pickers'
local finders = require 'telescope.finders'
local conf = require('telescope.config').values
local previewers = require 'telescope.previewers'
local actions = require 'telescope.actions'
local action_state = require 'telescope.actions.state'

-- async magic
local async = require 'plenary.async'
local sleep = require('plenary.async.util').sleep

local US = string.char(31)
local RS = string.char(30)

function M.create_telescope_workflow(opts)
  return function()
    vim.ui.input({
      prompt = opts.prompt_text,
    }, function(input)
      if not input or input == '' then
        return
      end

      local safe_input = input:gsub("'", "''")

      local query = opts.build_query(safe_input, US, RS)
      -- vim.print(query)
      db.query(
        query,
        vim.schedule_wrap(function(data)
          if not data or type(data) ~= 'table' or #data == 0 then
            vim.notify('No results found.', vim.log.levels.WARN)
            return
          end
          pickers
            .new({}, {
              prompt_title = opts.title,
              finder = finders.new_table {
                results = data,
                entry_maker = function(row)
                  return {
                    value = row,
                    display = row[opts.display_index],
                    ordinal = row[opts.display_index],
                  }
                end,
              },

              sorter = conf.generic_sorter {},
              previewer = previewers.new_buffer_previewer {
                title = 'Preview',
                define_preview = function(self, entry)
                  local bufnr = self.state.bufnr
                  local raw_text = entry.value[opts.data_index] or ''
                  local lines = vim.split(raw_text, '\n', { plain = true })
                  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
                  vim.bo[bufnr].filetype = opts.filetype
                end,
              },

              attach_mappings = function(prompt_bufnr)
                actions.select_default:replace(function()
                  local selection = action_state.get_selected_entry()
                  actions.close(prompt_bufnr)

                  vim.cmd 'vnew'
                  local buf = vim.api.nvim_get_current_buf()
                  vim.bo[buf].buftype = 'nofile'
                  vim.bo[buf].bufhidden = 'wipe'
                  vim.bo[buf].filetype = opts.filetype

                  local lines = vim.split(selection.value[opts.data_index], '\n', { plain = true })

                  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
                  if opts.filetype == 'json' and vim.fn.executable 'jq' == 1 then
                    vim.cmd '%!jq .'
                  end
                end)
                return true
              end,
            })
            :find()
        end)
      )
    end)
  end
end

-- WARN: This is highly unstable, i don't know how to get the ordinals to stop breaking my config
local async_db_query = async.wrap(db.query, 2)
function M.dynamic_db_picker(opts)
  return function()
    opts = opts or {}

    local debounce_ms = opts.debounce or 250

    db.with_connection(function(conn)
      pickers
        .new({}, {
          prompt_title = opts.title or 'DB Query',

          finder = finders.new_dynamic {
            fn = function(prompt)
              if not prompt or prompt == '' then
                return {}
              end

              -- debounce because the db must be treated with love and care
              -- (this pc is not strong enough for spamming queries every keystroke)
              sleep(debounce_ms)

              -- async db call moment
              local safe_input = prompt:gsub("'", "''")
              -- this is specific to psql
              -- TODO: try to make this generic ig, so i can use it with sqlite or something else
              local psql_header = string.format("\\set QUIET 1\n\\a \\t \\pset fieldsep '%s' \\pset recordsep '%s'\n", US, RS) -- must do this for performance

              local user_query = string.format(opts.query_template, safe_input)
              local final_query = psql_header .. user_query

              local raw_data = async_db_query(final_query)

              if not raw_data or type(raw_data) ~= 'table' then
                return {}
              end
              return raw_data
            end,

            entry_maker = function(row)
              return {
                value = row,
                display = tostring(row[opts.display_column] or 'UNKNOWN'),
                ordinal = tostring(row[opts.preview_column] or 'UNKNOWN'),
              }
            end,
          },
          sorter = conf.generic_sorter {},

          previewer = previewers.new_buffer_previewer {
            title = 'Preview',
            define_preview = function(self, entry)
              local bufnr = self.state.bufnr
              local raw_text = tostring(entry.value[opts.preview_column] or '')
              local lines = vim.split(raw_text, '\n', { plain = true })

              vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
              vim.bo[bufnr].filetype = opts.filetype or 'txt'
            end,
          },

          attach_mappings = function(prompt_bufnr)
            actions.select_default:replace(function()
              local selection = action_state.get_selected_entry()
              if not selection then
                return
              end

              actions.close(prompt_bufnr)

              vim.cmd 'vnew'
              local buf = vim.api.nvim_get_current_buf()
              vim.bo[buf].buftype = 'nofile'
              vim.bo[buf].bufhidden = 'wipe' -- pop it out of ze ram when it is :q
              vim.bo[buf].filetype = opts.filetype or 'txt'

              local raw_text = tostring(selection.value[opts.preview_column] or '')
              local lines = vim.split(raw_text, '\n', { plain = true })
              vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

              if opts.filetype == 'json' and vim.fn.executable 'jq' == 1 then
                vim.cmd '%!jq .'
              end
            end)

            return true
          end,
        })
        :find()
    end) -- to ensure there's the db connection url available because coroutines
    -- and UI elements drawing async is poison in neovim (:C)
  end
end

function M.static_db_picker(query, opts)
  return function()
    opts = opts or {}

    db.with_connection(function(conn)
      local psql_header = string.format("\\set QUIET 1\n\\a \\t \\pset fieldsep '%s' \\pset recordsep '%s'\n", US, RS)
      local final_query = psql_header .. query

      db.query(final_query, function(raw_data)
        if not raw_data or type(raw_data) ~= 'table' then
          vim.schedule(function()
            vim.notify('No data returned or query failed.', vim.log.levels.WARN)
          end)
          return
        end

        vim.schedule(function()
          pickers
            .new(opts, {
              prompt_title = opts.title or 'Static DB Query',

              finder = finders.new_table {
                results = raw_data,
                entry_maker = function(row)
                  return {
                    value = row,
                    display = tostring(row[opts.display_column] or 'UNKNOWN'),
                    ordinal = tostring(row[opts.ordinal_column] or row[opts.display_column] or 'UNKNOWN'),
                  }
                end,
              },
              sorter = conf.generic_sorter(opts),

              previewer = previewers.new_buffer_previewer {
                title = 'Preview',
                define_preview = function(self, entry)
                  local bufnr = self.state.bufnr
                  local raw_text = tostring(entry.value[opts.preview_column] or '')
                  local lines = vim.split(raw_text, '\n', { plain = true })

                  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
                  vim.bo[bufnr].filetype = opts.filetype or 'txt'
                end,
              },

              attach_mappings = function(prompt_bufnr)
                actions.select_default:replace(function()
                  local selection = action_state.get_selected_entry()
                  if not selection then
                    return
                  end

                  actions.close(prompt_bufnr)

                  vim.cmd 'vnew'
                  local buf = vim.api.nvim_get_current_buf()
                  vim.bo[buf].buftype = 'nofile'
                  vim.bo[buf].bufhidden = 'wipe'
                  vim.bo[buf].filetype = opts.filetype or 'txt'

                  local raw_text = tostring(selection.value[opts.preview_column] or '')
                  local lines = vim.split(raw_text, '\n', { plain = true })
                  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

                  if opts.filetype == 'json' and vim.fn.executable 'jq' == 1 then
                    vim.cmd '%!jq .'
                  end
                end)

                return true
              end,
            })
            :find()
        end)
      end)
    end)
  end
end

return M
