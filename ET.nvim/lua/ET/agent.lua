local M = {}
local config = require('ET.config')
local ui = require('ET.ui')
local tools = require('ET.tools')
local states = require('ET.states')

-- Tool definitions (OpenAI-compatible format)
local tool_definitions = {
	{
		type = 'function',
		['function'] = {
			name = 'find_files',
			description = 'Find files by name pattern in the project directory',
			parameters = {
				type = 'object',
				properties = {
					filenames = {
						type = 'array',
						items = { type = 'string' },
						description = 'List of filenames or glob patterns to search for',
					},
				},
				required = { 'filenames' },
			},
		},
	},
	{
		type = 'function',
		['function'] = {
			name = 'read_file',
			description = 'Read the contents of a file',
			parameters = {
				type = 'object',
				properties = {
					filepath = {
						type = 'string',
						description = 'Absolute path to the file',
					},
				},
				required = { 'filepath' },
			},
		},
	},
	{
		type = 'function',
		['function'] = {
			name = 'edit_file',
			description = 'Replace lines in a file between start_line and end_line with new contents',
			parameters = {
				type = 'object',
				properties = {
					filepath = { type = 'string' },
					start_line = { type = 'integer' },
					end_line = { type = 'integer' },
					contents = { type = 'string', description = 'New content to replace the lines with' },
				},
				required = { 'filepath', 'start_line', 'end_line', 'contents' },
			},
		},
	},
	{
		type = 'function',
		['function'] = {
			name = 'write_file',
			description = 'Write contents to a file (creates or overwrites)',
			parameters = {
				type = 'object',
				properties = {
					filepath = { type = 'string' },
					contents = { type = 'string', description = 'Content to write to the file' },
				},
				required = { 'filepath', 'contents' },
			},
		},
	},
}

-- Tool dispatcher
local function dispatch_tool(name, args)
	if name == 'find_files' then
		return tools.find_files(args.filenames)
	elseif name == 'read_file' then
		return tools.read_file(args.filepath)
	elseif name == 'edit_file' then
		return tools.edit_file(args.filepath, args.start_line, args.end_line, args.contents)
	elseif name == 'write_file' then
		return tools.write_file(args.filepath, args.contents)
	end
	return { error = 'Unknown tool: ' .. tostring(name) }
end

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

			-- Dispatch each tool call
			for _, tc in ipairs(tool_calls) do
				local ok, args = pcall(vim.fn.json_decode, tc['function'].arguments)
				local result
				if ok then
					local success, tool_result = pcall(dispatch_tool, tc['function'].name, args)
					if success then
						result = vim.fn.json_encode(tool_result)
					else
						result = vim.fn.json_encode({ error = tostring(tool_result) })
					end
				else
					result = vim.fn.json_encode({ error = 'Failed to parse tool arguments: ' .. tc['function'].arguments })
				end

				table.insert(msgs, {
					role = 'tool',
					tool_call_id = tc.id,
					content = result,
				})
			end

			-- Continue the loop
			loop(msgs)
		end, function(content)
			-- Final response (no more tool calls)
			vim.notify('ET.nvim: Done', vim.log.levels.INFO)
			states._current_prompt_context = {}
		end)
	end

	loop(messages)
end

return M
