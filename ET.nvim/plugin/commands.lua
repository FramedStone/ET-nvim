local agent = require('ET.agent')
local config = require('ET.config')
local ui = require('ET.ui')
local tools = require('ET.tools')
local states = require('ET.states')
local Popup = require('nui.popup')
local Menu = require('nui.menu')
local Input = require('nui.input')
local Tree = require('nui.tree')

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
	local win = vim.api.nvim_get_current_win()
	local buf = vim.api.nvim_win_get_buf(win)
	tools.select_files(function(paths)
		if vim.api.nvim_buf_is_valid(buf) then
			vim.api.nvim_buf_set_lines(buf, -1, -1, false, paths)
		end
	end)
end, { desc = 'Pick files and insert into current buffer' })

vim.api.nvim_create_user_command('ET', function(opts)
	local popup = agent.open_chat()
	if opts.range > 0 then
		local out = tools.select_line_of_codes(opts)
		if out and popup and popup.bufnr then
			vim.api.nvim_buf_set_lines(popup.bufnr, -1, -1, false, { out })
		end
	end
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

			-- Store full results for future reference
			bravesearch_result_popup._search_results = results
			states.set_bravesearch_results(results)
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

			-- Store library results in state
			states.context7.library_results = pruned

			-- Build tree nodes
			local nodes = {}
			for i, lib in ipairs(pruned) do
				local children = {
					Tree.Node({ id = 'title-' .. i, text = '  title: ' .. (lib.title or ''), _is_child = true }),
					Tree.Node({ id = 'date-' .. i, text = '  lastUpdateDate: ' .. (lib.lastUpdateDate or ''), _is_child = true }),
					Tree.Node({ id = 'stars-' .. i, text = '  stars: ' .. tostring(lib.stars or 0), _is_child = true }),
					Tree.Node({ id = 'branch-' .. i, text = '  branch: ' .. (lib.branch or ''), _is_child = true }),
				}
				local node = Tree.Node({ id = 'lib-' .. i, text = i .. '. ' .. (lib.id or ''), _lib_id = lib.id, _res = lib }, children)
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
				local node = Tree.Node({ id = 'doc-' .. i, text = i .. '. ' .. (snippet.codeTitle or ''), _url = snippet.codeId, _res = snippet }, children)
				node:expand()
				table.insert(nodes, node)
				table.insert(nodes, Tree.Node({ id = 'sep-' .. i, text = '', _is_separator = true }))
			end

			-- Store codeList and infoSnippets in state
			states.set_context7_docs(pruned, results.infoSnippets or {})

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
		states.ui.library_result_tree = library_result_tree
		states.ui.docs_library_input = context7_docs_library_input
		states.ui.docs_result_tree = docs_result_tree
		states.ui.docs_input = context7_docs_input

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
	if not states.ui.library_result_tree or not states.ui.docs_library_input then
		vim.notify('ETContext7AddToDocs: Open ETContext7 first', vim.log.levels.WARN)
		return
	end

	local tree = states.ui.library_result_tree
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

	local input = states.ui.docs_library_input
	if not input.winid then
		vim.notify('ETContext7AddToDocs: Docs library input not available', vim.log.levels.WARN)
		return
	end

	vim.api.nvim_buf_set_lines(input.bufnr, 0, -1, false, { lib_id })

	-- Focus docs query input
	if states.ui.docs_input and states.ui.docs_input.winid then
		vim.api.nvim_set_current_win(states.ui.docs_input.winid)
	end
end, { desc = 'Add selected library to docs input' })

-- Helper: open review popup for adding to system prompt or prompt context
local function open_review_popup(text, mode)
	-- Pretty-print JSON through jq
	local formatted = text
	local ok, result = pcall(function()
		local tmpfile = vim.fn.tempname()
		vim.fn.writefile({ text }, tmpfile)
		local out = vim.fn.system('jq "." ' .. vim.fn.shellescape(tmpfile))
		vim.fn.delete(tmpfile)
		if vim.v.shell_error == 0 then
			return out
		end
		error('jq failed')
	end)
	if ok then
		formatted = result
	end

	local popup = Popup({
		enter = true,
		focusable = true,
		position = '50%',
		zindex = 200,
		size = { width = '70%', height = '50%' },
		border = {
			style = 'rounded',
			text = {
				top = mode == 'system' and '[Add to System Prompt]' or '[Add to Prompt]',
				top_align = 'left',
			},
		},
		buf_options = {
			modifiable = true,
			readonly = false,
		},
		win_options = {
			relativenumber = true,
		},
	})

	popup:mount()
	vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, vim.split(formatted, '\n'))

	local function save_and_close()
		local lines = vim.api.nvim_buf_get_lines(popup.bufnr, 0, -1, false)
		local content = table.concat(lines, '\n'):gsub('^%s*(.-)%s*$', '%1')
		if content ~= '' then
			if mode == 'system' then
				states.add_to_system_prompt(content)
				vim.notify('ET.nvim: Added to system prompt')
			else
				agent.add(content)
				vim.notify('ET.nvim: Added to prompt context')
			end
		end
		popup:unmount()

		if mode == 'system' then
			vim.cmd('ETSystemPrompt')
		else
			agent.open_chat()
		end
	end

	popup:map('n', ':w<CR>', save_and_close, { noremap = true, nowait = true })
	popup:map('n', ':wq<CR>', save_and_close, { noremap = true, nowait = true })
	popup:map('n', 'q', function()
		popup:unmount()
	end, { noremap = true, nowait = true })
end

-- Helper: detect focused tree window and return selected node's data
local function get_focused_context()
	local win = vim.api.nvim_get_current_win()

	-- Check bravesearch result tree
	if states.ui.bravesearch_result_tree then
		local popup = states.ui.bravesearch_result_popup
		if popup and popup.winid == win then
			local node = states.ui.bravesearch_result_tree:get_node()
			if node and node._res then
				return vim.fn.json_encode({
					source = 'bravesearch',
					type = states.bravesearch.selected_type,
					result = node._res,
				})
			end
		end
	end

	-- Check context7 library result tree
	if states.ui.library_result_tree then
		local tree_win = nil
		for _, w in ipairs(vim.api.nvim_list_wins()) do
			local ok, buf = pcall(vim.api.nvim_win_get_buf, w)
			if ok and states.ui.library_result_tree.bufnr == buf then
				tree_win = w
				break
			end
		end
		if tree_win == win then
			local node = states.ui.library_result_tree:get_node()
			if node and node._res then
				return vim.fn.json_encode({
					source = 'context7',
					type = 'library',
					result = node._res,
				})
			end
		end
	end

	-- Check context7 docs result tree
	if states.ui.docs_result_tree then
		local tree_win = nil
		for _, w in ipairs(vim.api.nvim_list_wins()) do
			local ok, buf = pcall(vim.api.nvim_win_get_buf, w)
			if ok and states.ui.docs_result_tree.bufnr == buf then
				tree_win = w
				break
			end
		end
		if tree_win == win then
			local node = states.ui.docs_result_tree:get_node()
			if node and node._res then
				return vim.fn.json_encode({
					source = 'context7',
					type = 'docs',
					result = node._res,
				})
			end
		end
	end

	return nil
end

vim.api.nvim_create_user_command('ETAddToSystemPrompt', function()
	local context = get_focused_context()
	if context then
		open_review_popup(context, 'system')
	else
		vim.notify('ETAddToSystemPrompt: Focus a BraveSearch or Context7 result window. Use :ETSystemPrompt to edit the system prompt directly.', vim.log.levels.WARN)
	end
end, { desc = 'Add context to system prompt' })

vim.api.nvim_create_user_command('ETAddToPrompt', function()
	local context = get_focused_context()
	if context then
		open_review_popup(context, 'prompt')
	else
		vim.notify('ETAddToPrompt: Focus a BraveSearch or Context7 result window. Use :ET to open the chat and type a prompt directly.', vim.log.levels.WARN)
	end
end, { desc = 'Add context to current prompt' })

vim.api.nvim_create_user_command('ETSystemPrompt', function()
	local full_prompt = states.get_system_prompt()

	local lines = vim.split(full_prompt, '\n')
	local height = math.max(#lines + 2, 10)

	local popup = Popup({
		enter = true,
		focusable = true,
		position = '50%',
		zindex = 200,
		size = { width = '60%', height = height },
		border = {
			style = 'rounded',
			text = {
				top = '[System Prompt]',
				top_align = 'left',
			},
		},
		buf_options = {
			modifiable = true,
			readonly = false,
		},
		win_options = {
			relativenumber = true,
		},
	})

	popup:mount()
	vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, lines)
	local last_line = vim.api.nvim_buf_line_count(popup.bufnr)
	vim.api.nvim_win_set_cursor(popup.winid, { last_line, 0 })

	local function save_and_close()
		local new_lines = vim.api.nvim_buf_get_lines(popup.bufnr, 0, -1, false)
		local content = table.concat(new_lines, '\n'):gsub('%s*$', '')
		local cfg = config.get_config()
		cfg.system_prompt = content
		config.set_config(cfg)
		states._system_prompt_additions = {}
		states.save()
		popup:unmount()
		vim.notify('ET.nvim: System prompt updated')
	end

	popup:map('n', ':w<CR>', save_and_close, { noremap = true, nowait = true })
	popup:map('n', ':wq<CR>', save_and_close, { noremap = true, nowait = true })
	popup:map('n', 'q', function()
		popup:unmount()
	end, { noremap = true, nowait = true })
end, { desc = 'Edit system prompt' })

vim.api.nvim_create_user_command('ETInstallTools', function()
	tools.setup_external_tools()
end, { desc = 'Install External Tools' })
