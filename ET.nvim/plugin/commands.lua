local agent = require('ET.agent')
local config = require('ET.config')
local ui = require('ET.ui')
local tools = require('ET.tools')
local Popup = require('nui.popup')
local Menu = require('nui.menu')
local Input = require('nui.input')
local Tree = require('nui.tree')
local Line = require('nui.line')
local Text = require('nui.text')

vim.api.nvim_create_user_command('ETSwitchModel', function()
	local models = config.get_models()

	local model_items = {}
	for _, model in ipairs(models) do
		table.insert(model_items, { text = model })
	end

	ui.create_menu('Select Model', model_items, function(selected)
		local model_name = type(selected) == 'table' and selected.text or selected
		local cfg = config.get_config()
		cfg.model = model_name
		config.set_config(cfg)
		vim.notify('ET.nvim: Switched to model ' .. model_name)
	end, '30%', #model_items + 1)
end, { desc = 'Switch ET model' })

vim.api.nvim_create_user_command('ETEditSettings', function()
	config.set_config()
end, { desc = 'Edit ET configuration' })

vim.api.nvim_create_user_command('ETFilePicker', function()
	tools.select_files()
end, { desc = '' })

vim.api.nvim_create_user_command('ET', function(opts)
	tools.select_line_of_codes(opts)
	agent.open_chat()
end, { range = true, desc = 'Open ET Chat' })

vim.api.nvim_create_user_command('ETBraveSearch', function()
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
		border = { style = 'rounded', text = { top = '[Search Query]' } },
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

				-- For images/videos, override url with thumbnail src
				local result_copy = vim.tbl_deep_extend('force', {}, res)
				if selected_type == 'images' and result_copy.thumbnail then
					result_copy.url = result_copy.thumbnail
				elseif selected_type == 'videos' and result_copy.thumbnail then
					result_copy.url = result_copy.thumbnail
				end

				-- Create child node for URL
				local children = {}
				if url ~= '' then
					table.insert(
						children,
						Tree.Node({ id = 'url-' .. i, text = '  ' .. url, _is_child = true, _url = url })
					)
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

			-- Store full results on popup for future cherry-picking
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
		local count_input = Input({
			relative = 'cursor',
			position = { row = 1, col = 0 },
			size = 25,
			zindex = 200,
			border = {
				style = 'rounded',
				text = { top = '[Result Count]', top_align = 'left' },
			},
			win_options = {
				winhighlight = 'Normal:Normal,FloatBorder:Normal',
			},
		}, {
			prompt = 'count: ',
			default_value = '5',
			on_submit = function(value)
				local count = tonumber(value) or 5
				if count < 1 then
					count = 5
				end
				run_search(query, count)
			end,
			on_close = function()
				-- User cancelled, do nothing
			end,
		})

		count_input:map('n', '<Esc>', function()
			count_input:unmount()
		end, { noremap = true, nowait = true })

		count_input:mount()
	end

	-- Initialize tree after popup is mounted
	vim.defer_fn(function()
		if not bravesearch_result_popup.winid then
			return
		end

		-- Create initial tree with placeholder message
		result_tree = Tree({
			bufnr = bravesearch_result_popup.bufnr,
			nodes = {
				Tree.Node({ text = 'Enter query and press :w<CR> to search' }),
			},
			prepare_node = function(node)
				local line = Line()

				if node:has_children() then
					-- Parent node: show expand/collapse indicator + title
					local icon = node:is_expanded() and '  ' or '  '
					line:append(icon, 'SpecialChar')
					line:append(node.text, 'Title')
				elseif node._is_child then
					-- Child node: indented description or URL
					if node._url then
						line:append(node.text, 'Comment')
					else
						line:append(node.text, 'Normal')
					end
				else
					-- Simple text node (loading, error, placeholder)
					line:append(node.text)
				end

				return line
			end,
		})
		result_tree:render()

		-- Map <CR> to open URL from selected node
		bravesearch_result_popup:map('n', '<CR>', function()
			if not result_tree then
				return
			end
			local node = result_tree:get_node()
			if not node then
				return
			end

			-- If it's a parent node with _res, open its URL
			if node._res and node._res.url then
				vim.ui.open(node._res.url)
			-- If it's a child URL node, open its URL
			elseif node._url then
				vim.ui.open(node._url)
			-- If it's a parent with children, toggle expand/collapse
			elseif node:has_children() then
				if node:is_expanded() then
					node:collapse()
				else
					node:expand()
				end
				result_tree:render()
			end
		end, { noremap = true, nowait = true })

		-- Map <Esc> to do nothing (prevent popup from closing and breaking layout)
		bravesearch_result_popup:map('n', '<Esc>', function()
			-- Do nothing - keep popup open
		end, { noremap = true, nowait = true })

		-- Map l to expand node
		bravesearch_result_popup:map('n', 'l', function()
			if not result_tree then
				return
			end
			local node = result_tree:get_node()
			if node and node:has_children() and not node:is_expanded() then
				node:expand()
				result_tree:render()
			end
		end, { noremap = true, nowait = true })

		-- Map h to collapse node
		bravesearch_result_popup:map('n', 'h', function()
			if not result_tree then
				return
			end
			local node = result_tree:get_node()
			if node and node:has_children() and node:is_expanded() then
				node:collapse()
				result_tree:render()
			end
		end, { noremap = true, nowait = true })

		-- Map j/k for navigation (using native cursor movement)
		bravesearch_result_popup:map('n', 'j', 'j', { noremap = true, nowait = true })
		bravesearch_result_popup:map('n', 'k', 'k', { noremap = true, nowait = true })
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
end, { desc = 'Brave Search' })

vim.api.nvim_create_user_command('ETContext7', function()
	ui.create_menu('Context7', {
		{ text = 'library' },
		{ text = 'docs' },
	}, function(selected)
		local selected_text = type(selected) == 'table' and selected.text or selected
		if selected_text == 'library' then
			vim.defer_fn(function()
				local popup = Popup({
					position = '50%',
					size = { width = '60%', height = '40%' },
					enter = true,
					border = {
						style = 'rounded',
						text = {
							top = '[Library Search]',
						},
					},
					buf_options = {
						buftype = '',
						modifiable = true,
						readonly = false,
					},
				})
				popup:mount()
			end, 0)
		elseif selected_text == 'docs' then
			vim.defer_fn(function()
				local context_docs_library = Popup({
					border = {
						style = 'rounded',
						text = {
							top = 'Context Docs Library',
						},
					},
					buf_options = {
						buftype = '',
						modifiable = true,
						readonly = false,
					},
				})

				local context_docs_input = Popup({
					border = {
						style = 'rounded',
						text = {
							top = 'Context Docs Input',
						},
					},
					buf_options = {
						buftype = '',
						modifiable = true,
						readonly = false,
					},
				})

				ui.create_layout('90%', '85%', {
					{ component = context_docs_library, size = 50 },
					{ component = context_docs_input, size = 50 },
				}, 'col')
			end, 0)
		end
	end, 20, 3)
end, { desc = 'Context7' })

vim.api.nvim_create_user_command('ETInstallTools', function()
	tools.setup_external_tools()
end, { desc = 'Install External Tools' })
