local agent = require('ET.agent')
local config = require('ET.config')
local ui = require('ET.ui')
local tools = require('ET.tools')
local Popup = require('nui.popup')
local Menu = require('nui.menu')
local Input = require('nui.input')
local Tree = require('nui.tree')

-- Shared state for ETContext7 commands
local ctx7_state = {
	library_result_tree = nil,
	docs_library_input = nil,
	docs_result_tree = nil,
	docs_input = nil,
	docs_code_snippets = {},
	docs_info_snippets = {},
}

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

		result_tree = ui.create_tree(bravesearch_result_popup, 'Enter query and press :w<CR> to search', {
			keymaps = {
				['<CR>'] = function()
					if not result_tree then
						return
					end
					local node = result_tree:get_node()
					if not node then
						return
					end
					if node._res and node._res.url then
						vim.ui.open(node._res.url)
					elseif node._url then
						vim.ui.open(node._url)
					elseif node:has_children() then
						if node:is_expanded() then
							node:collapse()
						else
							node:expand()
						end
						result_tree:render()
					end
				end,
				['<Esc>'] = function() end,
			},
		})
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
	local library_result_tree = nil
	local docs_result_tree = nil

	-- Left panel: library search results
	local context7_library_result = Popup({
		border = { style = 'rounded', text = { top = 'Library Results' } },
		win_options = {
			winhighlight = 'Normal:Normal,FloatBorder:Normal,CursorLine:Visual',
			cursorline = true,
		},
		buf_options = { readonly = true, modifiable = false },
	})

	-- Left bottom: library search input
	local context7_library_input = Popup({
		border = { style = 'rounded', text = { top = '[Query]' } },
		buf_options = { modifiable = true, readonly = false },
	})

	-- Arrow separator popup
	local context7_arrow = Popup({
		focusable = false,
		border = { style = 'none' },
		buf_options = { modifiable = true, readonly = false },
		win_options = {
			winhighlight = 'Normal:Normal,FloatBorder:Normal',
		},
	})

	-- Right panel: docs search results
	local context7_docs_result = Popup({
		border = { style = 'rounded', text = { top = 'Docs Results' } },
		win_options = {
			winhighlight = 'Normal:Normal,FloatBorder:Normal,CursorLine:Visual',
			cursorline = true,
		},
		buf_options = { readonly = true, modifiable = false },
	})

	-- Right bottom left: docs library input
	local context7_docs_library_input = Popup({
		border = { style = 'rounded', text = { top = '[Library]' } },
		buf_options = { modifiable = true, readonly = false },
	})

	-- Right bottom right: docs query input
	local context7_docs_input = Popup({
		border = { style = 'rounded', text = { top = '[Query]' } },
		buf_options = { modifiable = true, readonly = false },
	})

	-- Build layout with create_layout (supports nested dir groups + TAB/S-TAB)
	local _, components = ui.create_layout('90%', '85%', {
		{
			dir = 'col',
			size = 49,
			{ component = context7_library_result, size = 90 },
			{ component = context7_library_input, size = 10, initial_focus = true },
		},
		{ component = context7_arrow, size = 2, focusable = false },
		{
			dir = 'col',
			size = 49,
			{ component = context7_docs_result, size = 90 },
			{
				dir = 'row',
				size = 10,
				{ component = context7_docs_library_input, size = 50 },
				{ component = context7_docs_input, size = 50 },
			},
		},
	}, 'row')

	-- Library search functions
	local function run_library_search(query, count)
		if library_result_tree then
			library_result_tree:set_nodes({ Tree.Node({ text = 'Searching...' }) })
			library_result_tree:render()
		end

		vim.defer_fn(function()
			local ok, results = pcall(tools.use_context7, 'library', query)
			if not ok then
				vim.notify('ETContext7 failed: ' .. results, vim.log.levels.ERROR)
				if library_result_tree then
					library_result_tree:set_nodes({ Tree.Node({ text = 'Error: ' .. results }) })
					library_result_tree:render()
				end
				return
			end

			if #results == 0 then
				vim.notify('No results found', vim.log.levels.WARN)
				if library_result_tree then
					library_result_tree:set_nodes({ Tree.Node({ text = 'No results found' }) })
					library_result_tree:render()
				end
				return
			end

			-- Filter out invalid results (stars == -1)
			local filtered = {}
			for _, lib in ipairs(results) do
				if lib.stars ~= -1 then
					table.insert(filtered, lib)
				end
			end

			-- Prune results to count
			local pruned = {}
			for i = 1, math.min(count, #filtered) do
				table.insert(pruned, filtered[i])
			end

			-- Build tree nodes
			local nodes = {}
			for i, lib in ipairs(pruned) do
				local children = {
					Tree.Node({ id = 'title-' .. i, text = '  title: ' .. (lib.title or ''), _is_child = true }),
					Tree.Node({ id = 'date-' .. i, text = '  lastUpdateDate: ' .. (lib.lastUpdateDate or ''), _is_child = true }),
					Tree.Node({ id = 'stars-' .. i, text = '  stars: ' .. tostring(lib.stars or 0), _is_child = true }),
					Tree.Node({ id = 'branch-' .. i, text = '  branch: ' .. (lib.branch or ''), _is_child = true }),
				}
				local node = Tree.Node({ id = 'lib-' .. i, text = i .. '. ' .. (lib.id or ''), _lib_id = lib.id }, children)
				node:expand()
				table.insert(nodes, node)
				table.insert(nodes, Tree.Node({ id = 'sep-' .. i, text = '', _is_separator = true }))
			end

			if library_result_tree then
				library_result_tree:set_nodes(nodes)
				library_result_tree:render()

				if context7_library_result.winid then
					vim.api.nvim_set_current_win(context7_library_result.winid)
					vim.api.nvim_win_set_cursor(context7_library_result.winid, { 1, 0 })
				end
			end
		end, 0)
	end

	local function execute_library_search()
		local query_lines = vim.api.nvim_buf_get_lines(context7_library_input.bufnr, 0, -1, false)
		local query = table.concat(query_lines, ' '):gsub('^%s*(.-)%s*$', '%1')
		if query == '' then
			vim.notify('ETContext7: Enter a query first', vim.log.levels.WARN)
			return
		end

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
				run_library_search(query, count)
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

	-- Docs search functions
	local function run_docs_search(lib_id, raw_query, count)
		if docs_result_tree then
			docs_result_tree:set_nodes({ Tree.Node({ text = 'Searching...' }) })
			docs_result_tree:render()
		end

		vim.defer_fn(function()
			local ok, results = pcall(tools.use_context7, 'docs', raw_query, lib_id)
			if not ok then
				vim.notify('ETContext7 docs failed: ' .. results, vim.log.levels.ERROR)
				if docs_result_tree then
					docs_result_tree:set_nodes({ Tree.Node({ text = 'Error: ' .. results }) })
					docs_result_tree:render()
				end
				return
			end

			local snippets = results.codeSnippets or {}
			if #snippets == 0 then
				vim.notify('No docs found', vim.log.levels.WARN)
				if docs_result_tree then
					docs_result_tree:set_nodes({ Tree.Node({ text = 'No docs found' }) })
					docs_result_tree:render()
				end
				return
			end

			-- Prune results to count
			local pruned = {}
			for i = 1, math.min(count, #snippets) do
				table.insert(pruned, snippets[i])
			end

			-- Build tree nodes
			local nodes = {}
			for i, snippet in ipairs(pruned) do
				local children = {
					Tree.Node({ id = 'lang-' .. i, text = '  codeLanguage: ' .. (snippet.codeLanguage or ''), _is_child = true }),
					Tree.Node({ id = 'id-' .. i, text = '  codeId: ' .. (snippet.codeId or ''), _is_child = true, _url = snippet.codeId }),
				}
				local node = Tree.Node({ id = 'doc-' .. i, text = i .. '. ' .. (snippet.codeTitle or ''), _url = snippet.codeId }, children)
				node:expand()
				table.insert(nodes, node)
				table.insert(nodes, Tree.Node({ id = 'sep-' .. i, text = '', _is_separator = true }))
			end

			-- Store codeList and infoSnippets in state
			ctx7_state.docs_code_snippets = pruned
			ctx7_state.docs_info_snippets = results.infoSnippets or {}

			if docs_result_tree then
				docs_result_tree:set_nodes(nodes)
				docs_result_tree:render()

				if context7_docs_result.winid then
					vim.api.nvim_set_current_win(context7_docs_result.winid)
					vim.api.nvim_win_set_cursor(context7_docs_result.winid, { 1, 0 })
				end
			end
		end, 0)
	end

	local function execute_docs_search()
		local lib_lines = vim.api.nvim_buf_get_lines(context7_docs_library_input.bufnr, 0, -1, false)
		local lib_id = table.concat(lib_lines, ' '):gsub('^%s*(.-)%s*$', '%1')
		if lib_id == '' then
			vim.notify('ETContext7: Enter a library ID first', vim.log.levels.WARN)
			return
		end

		local query_lines = vim.api.nvim_buf_get_lines(context7_docs_input.bufnr, 0, -1, false)
		local raw_query = table.concat(query_lines, ' '):gsub('^%s*(.-)%s*$', '%1')
		if raw_query == '' then
			vim.notify('ETContext7: Enter a query first', vim.log.levels.WARN)
			return
		end

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
				run_docs_search(lib_id, raw_query, count)
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

	-- Set arrow content after mount
	vim.defer_fn(function()
		if context7_arrow.winid then
			local arrow_h = vim.api.nvim_win_get_height(context7_arrow.winid)
			local arrow_w = vim.api.nvim_win_get_width(context7_arrow.winid)
			local mid = math.floor(arrow_h / 2) + 1
			local pad = string.rep(' ', math.floor(arrow_w / 2))
			local lines = {}
			for i = 1, arrow_h do
				lines[i] = i == mid and (pad .. '→') or ''
			end
			vim.api.nvim_buf_set_lines(context7_arrow.bufnr, 0, -1, false, lines)
		end
	end, 50)

	-- Initialize trees after mount
	vim.defer_fn(function()
		if not context7_library_result.winid or not context7_docs_result.winid then
			return
		end

		library_result_tree = ui.create_tree(context7_library_result, 'Search for a library to get started')
		docs_result_tree = ui.create_tree(context7_docs_result, 'Search for docs to get started')

		-- Store references for ETContext7AddToDocs
		ctx7_state.library_result_tree = library_result_tree
		ctx7_state.docs_library_input = context7_docs_library_input
		ctx7_state.docs_result_tree = docs_result_tree
		ctx7_state.docs_input = context7_docs_input

		-- Map :w<CR> on left-side components for library search
		context7_library_input:map('n', ':w<CR>', execute_library_search, { noremap = true, nowait = true })
		context7_library_result:map('n', ':w<CR>', execute_library_search, { noremap = true, nowait = true })

		-- Map <CR> to open library GitHub page
		context7_library_result:map('n', '<CR>', function()
			if not library_result_tree then
				return
			end
			local node = library_result_tree:get_node()
			if not node then
				return
			end
			if node._lib_id then
				vim.ui.open('https://github.com' .. node._lib_id)
			elseif node._url then
				vim.ui.open(node._url)
			elseif node:has_children() then
				if node:is_expanded() then
					node:collapse()
				else
					node:expand()
				end
				library_result_tree:render()
			end
		end, { noremap = true, nowait = true })

		-- Map :w<CR> on right-side components for docs search
		context7_docs_library_input:map('n', ':w<CR>', execute_docs_search, { noremap = true, nowait = true })
		context7_docs_input:map('n', ':w<CR>', execute_docs_search, { noremap = true, nowait = true })
		context7_docs_result:map('n', ':w<CR>', execute_docs_search, { noremap = true, nowait = true })

		-- Map <CR> on docs result to open codeId URL
		context7_docs_result:map('n', '<CR>', function()
			if not docs_result_tree then
				return
			end
			local node = docs_result_tree:get_node()
			if not node then
				return
			end
			if node._url then
				vim.ui.open(node._url)
			elseif node:has_children() then
				if node:is_expanded() then
					node:collapse()
				else
					node:expand()
				end
				docs_result_tree:render()
			end
		end, { noremap = true, nowait = true })
	end, 100)
end, { desc = 'Context7' })

vim.api.nvim_create_user_command('ETContext7AddToDocs', function()
	if not ctx7_state.library_result_tree or not ctx7_state.docs_library_input then
		vim.notify('ETContext7AddToDocs: Open ETContext7 first', vim.log.levels.WARN)
		return
	end

	local tree = ctx7_state.library_result_tree
	local node = tree:get_node()
	if not node then
		vim.notify('ETContext7AddToDocs: No result selected', vim.log.levels.WARN)
		return
	end

	local lib_id = node._lib_id
	if not lib_id then
		vim.notify('ETContext7AddToDocs: Select a library result', vim.log.levels.WARN)
		return
	end

	local input = ctx7_state.docs_library_input
	if not input.winid then
		vim.notify('ETContext7AddToDocs: Docs library input not available', vim.log.levels.WARN)
		return
	end

	vim.api.nvim_buf_set_lines(input.bufnr, 0, -1, false, { lib_id })

	-- Focus docs query input
	if ctx7_state.docs_input and ctx7_state.docs_input.winid then
		vim.api.nvim_set_current_win(ctx7_state.docs_input.winid)
	end
end, { desc = 'Add selected library to docs input' })

vim.api.nvim_create_user_command('ETInstallTools', function()
	tools.setup_external_tools()
end, { desc = 'Install External Tools' })
