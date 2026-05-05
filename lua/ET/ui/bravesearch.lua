local Popup = require('nui.popup')
local Menu = require('nui.menu')
local Tree = require('nui.tree')
local ui = require('ET.ui')
local tools = require('ET.tools')
local states = require('ET.states')

local M = {}

function M.open()
	local selected_type = 'web' -- default
	local result_tree = nil -- will hold the NuiTree instance

	-- Result popup with cursor line highlight
	local bravesearch_result_popup = Popup({
		border = { style = 'rounded', text = { top = 'Brave Search Results' } },
		win_options = {
			winhighlight = 'Normal:Normal,FloatBorder:Normal,CursorLine:Visual',
			cursorline = true,
		},
		buf_options = { readonly = true, modifiable = false },
	})

	local bravesearch_input = Popup({
		border = { style = 'rounded', text = { top = '[Query]' } },
		buf_options = { modifiable = true, readonly = false },
	})

	local bravesearch_type_menu = Menu({
		border = { style = 'rounded', text = { top = '[Type]' } },
	}, {
		lines = {
			Menu.item('web'),
			Menu.item('news'),
			Menu.item('images'),
			Menu.item('videos'),
		},
		keymap = { focus_next = { 'j', '<Down>' }, focus_prev = { 'k', '<Up>' } },
		on_change = function(item, menu)
			if item and item.text then
				selected_type = item.text
				states.bravesearch.selected_type = item.text
			end
		end,
	})

	-- Extracted search execution function (callable from any box)
	local function run_search(query, count)
		-- Show loading state
		if result_tree then
			result_tree:set_nodes({ Tree.Node({ text = 'Searching...' }) })
			result_tree:render()
		end

		-- Run search asynchronously
		vim.defer_fn(function()
			local ok, results = pcall(tools.use_brave_search, selected_type, query, count)
			if not ok then
				vim.notify('ETBraveSearch failed: ' .. results, vim.log.levels.ERROR)
				if result_tree then
					result_tree:set_nodes({ Tree.Node({ text = 'Error: ' .. results }) })
					result_tree:render()
				end
				return
			end

			if #results == 0 then
				vim.notify('No results found', vim.log.levels.WARN)
				if result_tree then
					result_tree:set_nodes({ Tree.Node({ text = 'No results found' }) })
					result_tree:render()
				end
				return
			end

			-- Build tree nodes: each result shows title + url with separator
			local result_nodes = {}
			for i, res in ipairs(results) do
				local title = res.title or 'No title'
				local url = res.url or ''

				local result_copy = vim.tbl_deep_extend('force', {}, res)
				if selected_type == 'images' and result_copy.thumbnail then
					result_copy.url = result_copy.thumbnail
				elseif selected_type == 'videos' and result_copy.thumbnail then
					result_copy.url = result_copy.thumbnail
				end

				-- Build children
				local children = {}
				if url ~= '' then
					table.insert(children, Tree.Node({ id = 'url-' .. i, text = '  ' .. url, _is_child = true, _url = url }))
				end

				-- Parent node stores the full result data
				local node = Tree.Node({ id = 'result-' .. i, text = i .. '. ' .. title, _res = result_copy }, children)
				node:expand()
				table.insert(result_nodes, node)

				-- Add blank separator line between results
				table.insert(result_nodes, Tree.Node({ id = 'sep-' .. i, text = '', _is_separator = true }))
			end

			-- Update tree with results
			if result_tree then
				result_tree:set_nodes(result_nodes)
				result_tree:render()

				-- Focus cursor on result popup for immediate browsing
				if bravesearch_result_popup.winid then
					vim.api.nvim_set_current_win(bravesearch_result_popup.winid)
					-- Move cursor to first result
					vim.api.nvim_win_set_cursor(bravesearch_result_popup.winid, { 1, 0 })
				end
			end

			-- Store full results for future reference
			bravesearch_result_popup._search_results = results
		end, 0)
	end

	local function execute_search()
		local query_lines = vim.api.nvim_buf_get_lines(bravesearch_input.bufnr, 0, -1, false)
		local query = table.concat(query_lines, ' '):gsub('^%s*(.-)%s*$', '%1')
		if query == '' then
			vim.notify('ETBraveSearch: Enter a query first', vim.log.levels.WARN)
			return
		end

		-- Prompt for count with temporary input
		ui.prompt_count(function(count) run_search(query, count) end)
	end

	-- Initialize tree after popup is mounted
	vim.defer_fn(function()
		if not bravesearch_result_popup.winid then
			return
		end

		result_tree = ui.create_tree(bravesearch_result_popup, 'Enter query and press :w<CR> to search', {
			on_open = function(node)
				if node._res and node._res.url then
					vim.ui.open(node._res.url)
					return true
				end
				if node._url then
					vim.ui.open(node._url)
					return true
				end
			end,
			keymaps = {
				['<Esc>'] = function() end,
			},
		})

		-- Store bravesearch UI references in states
		states.ui.bravesearch_result_popup = bravesearch_result_popup
		states.ui.bravesearch_result_tree = result_tree
	end, 100)

	-- Layout (handles mounting all components)
	local _, components = ui.create_layout('90%', '85%', {
		{ component = bravesearch_result_popup, size = 80 },
		{
			dir = 'row',
			size = 20,
			{ component = bravesearch_input, size = 60, initial_focus = true },
			{ component = bravesearch_type_menu, size = 40 },
		},
	}, 'col')

	-- Map :w<CR> to ALL components so search can be triggered from any box
	for _, comp in ipairs(components) do
		comp:map('n', ':w<CR>', execute_search, { noremap = true, nowait = true })
	end
end

return M
