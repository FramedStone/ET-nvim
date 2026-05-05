local agent = require('ET.agent')
local config = require('ET.config')
local ui = require('ET.ui')
local tools = require('ET.tools')
local states = require('ET.states')
local Popup = require('nui.popup')
local bravesearch = require('ET.ui.bravesearch')
local context7 = require('ET.ui.context7')

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
		config.save_config(cfg)
		vim.notify('ET.nvim: Switched to model ' .. model_name)
	end, '30%', #model_items + 1)
end, { desc = 'Switch ET model' })

vim.api.nvim_create_user_command('ETEditSettings', function()
	config.edit_config_ui()
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
	local source_buf = vim.api.nvim_get_current_buf()
	local popup = agent.open_chat()
	if opts.range > 0 then
		local out = tools.select_line_of_codes(opts, source_buf)
		if out and popup and popup.bufnr then
			vim.api.nvim_buf_set_lines(popup.bufnr, -1, -1, false, vim.split(out, '\n'))
			ui.focus_last_line(popup)
		end
	end
end, { range = true, desc = 'Open ET Chat' })

vim.api.nvim_create_user_command('ETBraveSearch', function()
	bravesearch.open()
end, { desc = 'Brave Search' })

vim.api.nvim_create_user_command('ETContext7', function()
	context7.open()
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
		local content = ui.trim(table.concat(lines, '\n'))
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

	ui.bind_save_close_keys(popup, save_and_close)
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

	-- Check web_fetch results popup
	if states.ui.web_fetch_popup then
		local popup = states.ui.web_fetch_popup
		if popup.winid and popup.winid == win then
			local idx = states.ui.web_fetch_popup_index or 1
			local results = states.web_fetch_history or {}
			if results[idx] then
				local page = results[idx]
				return vim.fn.json_encode({
					source = 'web_fetch',
					url = page.url,
					title = page.title,
				})
			end
		end
	end

	return nil
end

vim.api.nvim_create_user_command('ETWebFetchResults', function()
	agent.show_web_fetch_results()
end, { desc = 'Show web_fetch results from the last agent run' })

vim.api.nvim_create_user_command('ETAddToSystemPrompt', function(opts)
	local context
	if opts.range > 0 then
		local lines = vim.api.nvim_buf_get_lines(0, opts.line1 - 1, opts.line2, false)
		context = table.concat(lines, '\n')
	else
		context = get_focused_context()
	end
	if context and context ~= '' then
		open_review_popup(context, 'system')
	else
		vim.notify('ETAddToSystemPrompt: Select text with visual mode, or focus a BraveSearch/Context7/Web Fetch Results window. Use :ETSystemPrompt to edit the system prompt directly.', vim.log.levels.WARN)
	end
end, { range = true, desc = 'Add context to system prompt' })

vim.api.nvim_create_user_command('ETAddToPrompt', function(opts)
	local context
	if opts.range > 0 then
		local lines = vim.api.nvim_buf_get_lines(0, opts.line1 - 1, opts.line2, false)
		context = table.concat(lines, '\n')
	else
		context = get_focused_context()
	end
	if context and context ~= '' then
		open_review_popup(context, 'prompt')
	else
		vim.notify('ETAddToPrompt: Select text with visual mode, or focus a BraveSearch/Context7/Web Fetch Results window. Use :ET to open the chat and type a prompt directly.', vim.log.levels.WARN)
	end
end, { range = true, desc = 'Add context to current prompt' })

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
	ui.focus_last_line(popup)

	local function save_and_close()
		local new_lines = vim.api.nvim_buf_get_lines(popup.bufnr, 0, -1, false)
		local content = table.concat(new_lines, '\n'):gsub('%s*$', '')
		local cfg = config.get_config()
		cfg.system_prompt = content
		config.save_config(cfg)
		states._system_prompt_additions = {}
		states.save()
		popup:unmount()
		vim.notify('ET.nvim: System prompt updated')
	end

	ui.bind_save_close_keys(popup, save_and_close)
end, { desc = 'Edit system prompt' })

vim.api.nvim_create_user_command('ETInstallTools', function()
	tools.setup_external_tools()
end, { desc = 'Install External Tools' })
