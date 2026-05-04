local M = {}
local config = require('ET.config')
local ui = require('ET.ui')
local tools = require('ET.tools')
local states = require('ET.states')

-- Initialize: check for model, onboard if needed
function M.init()
	local cfg = config.get_config()
	if cfg.model == vim.NIL then
		local models = config.get_models()
		if #models > 0 then
			cfg.model = models[1]
			config.set_config(cfg)
		else
			config.set_config()
		end
	end
end

local function register_chat_keymaps(popup)
	local function close_chat()
		if popup.bufnr and vim.api.nvim_buf_is_valid(popup.bufnr) then
			states.ui.chat_buffer_lines = vim.api.nvim_buf_get_lines(popup.bufnr, 0, -1, false)
		end
		popup:unmount()
		ui._active_components[popup] = nil
		states.ui.chat_popup = nil
	end

	popup:map('n', 'q', close_chat, { noremap = true, nowait = true })
	popup:map('n', ':q<CR>', close_chat, { noremap = true, nowait = true })
	popup:map('n', ':w<CR>', function()
		M.prompt()
	end, { noremap = true, nowait = true })
	popup:map('n', ':wq<CR>', function()
		M.prompt()
	end, { noremap = true, nowait = true })
end

local function ensure_chat_popup()
	local old = states.ui.chat_popup
	if old then
		ui._active_components[old] = nil
		pcall(old.unmount, old)
		states.ui.chat_popup = nil
	end

	local popup = ui.create_popup('', '80%', '70%')
	register_chat_keymaps(popup)

	local saved = states.ui.chat_buffer_lines
	if saved and #saved > 0 then
		vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, saved)
	end

	states.ui.chat_popup = popup
	return popup
end

-- Open or reuse the chat popup
function M.open_chat()
	local popup = ensure_chat_popup()

	local context = states.get_prompt_context()
	if context ~= '' then
		local new_lines = {}
		for _, line in ipairs(vim.split(context, '\n')) do
			if line ~= '' then
				table.insert(new_lines, line)
			end
		end
		if #new_lines > 0 then
			local existing = vim.api.nvim_buf_get_lines(popup.bufnr, 0, -1, false)
			local has_content = false
			for _, line in ipairs(existing) do
				if line ~= '' then
					has_content = true
					break
				end
			end
			if has_content then
				vim.api.nvim_buf_set_lines(popup.bufnr, -1, -1, false, { '' })
			end
			vim.api.nvim_buf_set_lines(popup.bufnr, -1, -1, false, new_lines)
		end
	end

	vim.schedule(function()
		if popup.winid then
			vim.api.nvim_set_current_win(popup.winid)
			local last_line = vim.api.nvim_buf_line_count(popup.bufnr)
			vim.api.nvim_win_set_cursor(popup.winid, { last_line, 0 })
		end
	end)
	return popup
end

-- Add content to current prompt context
function M.add(content)
	states.add_to_prompt(content)
end

-- Get popup buffer content
local function get_popup_content()
	local popup = states.ui.chat_popup
	if not popup or not popup.bufnr then
		return ''
	end
	local lines = vim.api.nvim_buf_get_lines(popup.bufnr, 0, -1, false)
	return table.concat(lines, '\n'):gsub('^%s*(.-)%s*$', '%1')
end

-- Shows paginated web_fetch results popup after agent completes.
-- Exposed as M.show_web_fetch_results for :ETWebFetchResults command.
function M.show_web_fetch_results()
	local results = states.web_fetch_history
	if #results == 0 then
		-- vim.notify('ET.nvim: No web_fetch results to show', vim.log.levels.WARN)
		return
	end

	-- Close existing popup if any
	if states.ui.web_fetch_popup then
		pcall(states.ui.web_fetch_popup.unmount, states.ui.web_fetch_popup)
		ui._active_components[states.ui.web_fetch_popup] = nil
		states.ui.web_fetch_popup = nil
	end

	local current_index = 1
	local popup = ui.create_popup('Web Fetch Results', '85%', '80%')
	states.ui.web_fetch_popup = popup
	states.ui.web_fetch_popup_index = 1

	local function render_page(idx)
		local page = results[idx]
		local header = string.format('Page %d/%d \226\128\148 URL: %s', idx, #results, page.url)
		local title_line = 'Title: ' .. (page.title ~= '' and page.title or '(no title)')
		local meta = string.format(
			'Lines: %d cached / %d total%s',
			#page.lines,
			page.total_lines,
			page.truncated and ' (truncated)' or ''
		)
		local sep = string.rep('\226\148\128', 60)

		local content_lines = {
			header,
			title_line,
			meta,
			sep,
			'',
		}
		-- Show first 500 lines in the popup (full content is in results)
		local show_count = math.min(500, #page.lines)
		for i = 1, show_count do
			table.insert(content_lines, page.lines[i])
		end
		if show_count < #page.lines then
			table.insert(content_lines, '')
			table.insert(
				content_lines,
				string.format('... %d more lines (use web_fetch(url, "query") to search)', #page.lines - show_count)
			)
		end

		vim.api.nvim_buf_set_option(popup.bufnr, 'modifiable', true)
		vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, content_lines)
		vim.api.nvim_buf_set_option(popup.bufnr, 'modifiable', false)
		vim.api.nvim_buf_set_option(popup.bufnr, 'readonly', true)

		pcall(vim.api.nvim_win_set_cursor, popup.winid, { 1, 0 })
		states.ui.web_fetch_popup_index = idx
	end

	render_page(1)

	local function nav_next()
		if current_index < #results then
			current_index = current_index + 1
			render_page(current_index)
		end
	end

	local function nav_prev()
		if current_index > 1 then
			current_index = current_index - 1
			render_page(current_index)
		end
	end

	local function close()
		if popup.bufnr and vim.api.nvim_buf_is_valid(popup.bufnr) then
			pcall(popup.unmount, popup)
		end
		ui._active_components[popup] = nil
		states.ui.web_fetch_popup = nil
	end

	local function add_to_prompt()
		local page = results[current_index]
		local text = vim.fn.json_encode({
			source = 'web_fetch',
			url = page.url,
			title = page.title,
		})
		M.add(text)
		vim.notify('ET.nvim: Added web_fetch result to prompt context', vim.log.levels.INFO)
	end

	local function add_to_system_prompt()
		local page = results[current_index]
		local text = vim.fn.json_encode({
			source = 'web_fetch',
			url = page.url,
			title = page.title,
		})
		states.add_to_system_prompt(text)
		vim.notify('ET.nvim: Added web_fetch result to system prompt', vim.log.levels.INFO)
	end

	popup:map('n', 'l', nav_next, { noremap = true, nowait = true })
	popup:map('n', 'h', nav_prev, { noremap = true, nowait = true })
	popup:map('n', 'q', close, { noremap = true, nowait = true })
	popup:map('n', ':q<CR>', close, { noremap = true, nowait = true })
	popup:map('n', 'a', add_to_prompt, { noremap = true, nowait = true })
	popup:map('n', 'A', add_to_system_prompt, { noremap = true, nowait = true })
	popup:map('n', ':w<CR>', function()
		vim.cmd('ETAddToPrompt')
	end, { noremap = true, nowait = true })
	popup:map('n', ':wq<CR>', function()
		vim.cmd('ETAddToSystemPrompt')
	end, { noremap = true, nowait = true })
end

-- Agent prompt loop (tool-only, no streaming to UI)
function M.prompt()
	local user_input = get_popup_content()
	if user_input == '' then
		return
	end

	local popup = states.ui.chat_popup
	if popup then
		ui._active_components[popup] = nil
		pcall(popup.unmount, popup)
		states.ui.chat_popup = nil
	end
	states.ui.chat_buffer_lines = {}

	-- Clear previous web_fetch history for fresh agent run
	states.web_fetch_history = {}

	vim.notify('ET.nvim: Processing...', vim.log.levels.INFO)

	local full_input = user_input
	local pending = states.get_prompt_context()
	if pending ~= '' then
		full_input = pending .. '\n\n' .. user_input
	end

	local messages = {
		{ role = 'system', content = states.get_system_prompt() },
		{ role = 'user', content = full_input },
	}

	local function loop(msgs)
		config._prompt(msgs, function(tool_calls)
			-- Tool calls received
			local assistant_msg = {
				role = 'assistant',
				tool_calls = {},
			}

			for _, tc in ipairs(tool_calls) do
				table.insert(assistant_msg.tool_calls, {
					id = tc.id,
					type = tc.type,
					['function'] = {
						name = tc['function'].name,
						arguments = tc['function'].arguments,
					},
				})
			end

			table.insert(msgs, assistant_msg)

			local should_stop = false

			for _, tc in ipairs(tool_calls) do
				local tool_name = tc['function'].name
				vim.notify('ET.nvim: Calling tool → ' .. tool_name, vim.log.levels.INFO)
				local ok, args = pcall(vim.fn.json_decode, tc['function'].arguments)
				local result
				if ok then
					local success, tool_result = pcall(tools.dispatch, tool_name, args)
					if success then
						result = vim.fn.json_encode(tool_result)
						if tool_result and tool_result.stop then
							should_stop = true
							vim.notify('Agent: ' .. (tool_result.message or ''), vim.log.levels.INFO)
						end
					else
						result = vim.fn.json_encode({ error = tostring(tool_result) })
					end
				else
					result =
						vim.fn.json_encode({ error = 'Failed to parse tool arguments: ' .. tc['function'].arguments })
				end

				table.insert(msgs, {
					role = 'tool',
					tool_call_id = tc.id,
					content = result,
				})
			end

			if should_stop then
				states._current_prompt_context = {}
				if #states.pending_edits > 0 then
					local review = require('ET.review')
					review.review(states.pending_edits, function()
						states.pending_edits = {}
						M.show_web_fetch_results()
					end)
				else
					M.show_web_fetch_results()
				end
				return
			end

			loop(msgs)
		end, function(content)
			-- Final response (no more tool calls)
			vim.notify('ET.nvim: Done', vim.log.levels.INFO)
			if content and content ~= '' and content ~= 'Done' then
				vim.notify('Agent: ' .. content, vim.log.levels.INFO)
			end
			states._current_prompt_context = {}

			if #states.pending_edits > 0 then
				local review = require('ET.review')
				review.review(states.pending_edits, function()
					states.pending_edits = {}
					M.show_web_fetch_results()
				end)
			else
				M.show_web_fetch_results()
			end
		end, { tools = tools.tool_definitions })
	end

	loop(messages)
end

return M
