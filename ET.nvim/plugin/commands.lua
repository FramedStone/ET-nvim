local agent = require('ET.agent')
local config = require('ET.config')
local ui = require('ET.ui')
local tools = require('ET.tools')
local Popup = require('nui.popup')
local Menu = require('nui.menu')

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
	end, 25, #model_items + 1)
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

	-- Result menu (hyperlink style: title only, URL in _res)
	local bravesearch_result_menu = Menu({
		border = { style = 'rounded', text = { top = 'Brave Search Results' } },
		win_options = { winhighlight = 'Normal:Normal,FloatBorder:Normal' },
	}, {
		lines = { Menu.item('Enter query and press :w<CR> to search') },
		max_width = 80,
		max_height = 20, -- Scrollable when > 20 items
		keymap = {
			focus_next = { 'j', '<Down>' },
			focus_prev = { 'k', '<Up>' },
			close = {}, -- Disable auto-close to prevent unmount
			submit = {}, -- Disable auto-submit to prevent unmount
		},
		on_close = function() end, -- Don't unmount on close
	})
	-- NO mount() call - let Layout handle mounting

	-- Manually map <CR> after menu is mounted to open URL without unmounting
	vim.defer_fn(function()
		if bravesearch_result_menu.winid then
			bravesearch_result_menu:map('n', '<CR>', function()
				local node = bravesearch_result_menu.tree:get_node()
				if node and node._res and node._res.url then
					vim.ui.open(node._res.url)
				end
			end, { noremap = true, nowait = true })
			-- Map <Esc> to do nothing (prevent menu from closing and breaking layout)
			bravesearch_result_menu:map('n', '<Esc>', function()
				-- Do nothing - keep menu open
			end, { noremap = true, nowait = true })
		end
	end, 100)

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
			-- Fires on j/k navigation - updates type without unmount
			if item and item.text then
				selected_type = item.text
			end
		end,
	})

	-- Map :w<CR> in bravesearch_input to execute search
	bravesearch_input:map('n', ':w<CR>', function()
		local query_lines = vim.api.nvim_buf_get_lines(bravesearch_input.bufnr, 0, -1, false)
		local query = table.concat(query_lines, ' '):gsub('^%s*(.-)%s*$', '%1')
		if query == '' then
			vim.notify('ETBraveSearch: Enter a query first', vim.log.levels.WARN)
			return
		end

		-- Show loading state in the SAME menu (with safety check)
		if bravesearch_result_menu.tree then
			bravesearch_result_menu.tree:set_nodes({ Menu.item('Searching...') })
			bravesearch_result_menu.tree:render()
		end

		-- Run search asynchronously
		vim.defer_fn(function()
			local ok, results = pcall(tools.use_brave_search, selected_type, query, 5)
			if not ok then
				vim.notify('ETBraveSearch failed: ' .. results, vim.log.levels.ERROR)
				if bravesearch_result_menu.tree then
					bravesearch_result_menu.tree:set_nodes({ Menu.item('Error: ' .. results) })
					bravesearch_result_menu.tree:render()
				end
				return
			end

			if #results == 0 then
				vim.notify('No results found', vim.log.levels.WARN)
				if bravesearch_result_menu.tree then
					bravesearch_result_menu.tree:set_nodes({ Menu.item('No results found') })
					bravesearch_result_menu.tree:render()
				end
				return
			end

			-- Build result items: display title only (hyperlink style), store full result in _res
			local result_items = {}
			for _, res in ipairs(results) do
				local title = res.title or 'No title'
				table.insert(result_items, Menu.item(title, { _res = res }))
			end

			-- Update menu dynamically (same menu, no unmount/remount)
			if bravesearch_result_menu.tree then
				bravesearch_result_menu.tree:set_nodes(result_items)
				bravesearch_result_menu.tree:render()

				-- Focus cursor on result menu for immediate browsing
				if bravesearch_result_menu.winid then
					vim.api.nvim_set_current_win(bravesearch_result_menu.winid)
				end
			end

			-- Store full results on menu for future cherry-picking
			bravesearch_result_menu._search_results = results

			-- Don't unmount input/type menu - causes layout to close
			-- They remain mounted but are hidden behind the result menu
		end, 0)
	end, { noremap = true, nowait = true })

	-- Layout (handles mounting all components)
	ui.create_layout(70, 30, {
		{ component = bravesearch_result_menu, size = 80 },
		{
			dir = 'row',
			size = 20,
			{ component = bravesearch_input, size = 60, initial_focus = true },
			{ component = bravesearch_type_menu, size = 40 },
		},
	}, 'col')
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
					size = { width = 60, height = 10 },
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

				ui.create_layout(80, 30, {
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
