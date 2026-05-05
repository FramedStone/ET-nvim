local Popup = require('nui.popup')
local Tree = require('nui.tree')
local ui = require('ET.ui')
local tools = require('ET.tools')
local states = require('ET.states')

local M = {}

function M.open()
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

		ui.prompt_count(function(count) run_library_search(query, count) end)
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

		ui.prompt_count(function(count) run_docs_search(lib_id, raw_query, count) end)
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

		library_result_tree = ui.create_tree(context7_library_result, 'Search for a library to get started', {
			on_open = function(node)
				if node._lib_id then
					vim.ui.open('https://github.com' .. node._lib_id)
					return true
				end
				if node._url then
					vim.ui.open(node._url)
					return true
				end
			end,
		})
		docs_result_tree = ui.create_tree(context7_docs_result, 'Search for docs to get started', {
			on_open = function(node)
				if node._url then
					vim.ui.open(node._url)
					return true
				end
			end,
		})

		-- Store references for ETContext7AddToDocs
		states.ui.library_result_tree = library_result_tree
		states.ui.docs_library_input = context7_docs_library_input
		states.ui.docs_result_tree = docs_result_tree
		states.ui.docs_input = context7_docs_input

		-- Map :w<CR> on left-side components for library search
		context7_library_input:map('n', ':w<CR>', execute_library_search, { noremap = true, nowait = true })
		context7_library_result:map('n', ':w<CR>', execute_library_search, { noremap = true, nowait = true })

		-- Map :w<CR> on right-side components for docs search
		context7_docs_library_input:map('n', ':w<CR>', execute_docs_search, { noremap = true, nowait = true })
		context7_docs_input:map('n', ':w<CR>', execute_docs_search, { noremap = true, nowait = true })
		context7_docs_result:map('n', ':w<CR>', execute_docs_search, { noremap = true, nowait = true })
	end, 100)
end

return M
