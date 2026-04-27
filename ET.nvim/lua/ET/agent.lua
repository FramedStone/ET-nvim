local M = {}
local chat_ui
local chat_components
local layout_components
local layout_boxes
local chat_history = {}
local config = require('ET.config')
local ui = require('ET.ui')
local tools = require('ET.tools')

-- Set first model as default model
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

	-- load chat ui and hide
	local Popup = require('nui.popup')
	local temp_history = Popup({
		border = {
			style = 'rounded',
			text = {
				top = 'Temp History',
				top_align = 'center',
			},
		},
		win_options = {
			relativenumber = true,
		},
	})

	local main_input = Popup({
		border = {
			style = 'rounded',
			text = {
				top = '[Input]',
				top_align = 'center',
			},
		},
		buf_options = {
			buftype = '',
			modifiable = true,
			readonly = false,
		},
	})

	local brave_input = Popup({
		border = {
			style = 'rounded',
			text = {
				top = 'Brave Search',
			},
		},
		buf_options = {
			buftype = '',
			modifiable = true,
			readonly = false,
		},
	})

	local context_input = Popup({
		border = {
			style = 'rounded',
			text = {
				top = 'Context7',
			},
		},
		buf_options = {
			buftype = '',
			modifiable = true,
			readonly = false,
		},
	})

	chat_components = {
		temp_history = temp_history,
		main_input = main_input,
		brave_input = brave_input,
		context_input = context_input,
	}

	chat_ui, layout_components, layout_boxes = ui.create_layout(100, 40, {
		{ dir = 'col', size = 70, { component = temp_history, size = 90 }, { component = main_input, size = 10 } },
		{ dir = 'col', size = 30, { component = brave_input, size = 50 }, { component = context_input, size = 50 } },
	}, 'row')

	vim.schedule(function()
		chat_ui:hide()
	end)
end

function M.open_chat()
	if not chat_ui then
		M.init()
	end
	chat_ui:show()

	local temp_history_bufnr = chat_components.temp_history.bufnr
	vim.api.nvim_buf_set_lines(temp_history_bufnr, 0, -1, false, {})

	for _, msg in ipairs(chat_history) do
		local lines = vim.split(msg.content, '\n', { plain = true })
		for i, line in ipairs(lines) do
			lines[i] = (i == 1) and '[' .. msg.role .. ']: ' .. line or line
		end
		vim.api.nvim_buf_set_lines(temp_history_bufnr, -1, -1, false, lines)
		if msg.role == 'assistant' then
			vim.api.nvim_buf_set_lines(temp_history_bufnr, -1, -1, false, { '---' })
		end
	end

	ui.rebind_keymaps(layout_components, layout_boxes, chat_ui, {
		on_submit = function()
			M.prompt()
		end,
	})
	vim.schedule(function()
		if chat_components and chat_components.main_input then
			vim.api.nvim_set_current_win(chat_components.main_input.winid)
		end
	end)
end

function M.prompt()
	local temp_history_bufnr = chat_components.temp_history.bufnr
	local main_input_bufnr = chat_components.main_input.bufnr

	local input_lines = vim.api.nvim_buf_get_lines(main_input_bufnr, 0, -1, false)
	if #input_lines == 0 then
		return
	end

	local contents = {}
	local temp_lines = vim.api.nvim_buf_get_lines(temp_history_bufnr, 0, -1, false)
	local current_role = nil
	for _, line in ipairs(temp_lines) do
		if line == '---' then
			current_role = nil
		else
			local role, rest = line:match('^%[([^%]]+)%]:%s*(.*)')
			if role then
				current_role = role
				if rest and rest ~= '' then
					table.insert(contents, { role = current_role, content = rest })
				end
			elseif current_role then
				local existing = contents[#contents]
				if existing and existing.role == current_role then
					existing.content = existing.content .. '\n' .. line
				else
					table.insert(contents, { role = current_role, content = line })
				end
			end
		end
	end

	local new_input = table.concat(input_lines, '\n')
	table.insert(contents, { role = 'user', content = new_input })

	chat_history = contents

	local user_msg_lines = vim.split(new_input, '\n', { plain = true })
	for i, line in ipairs(user_msg_lines) do
		user_msg_lines[i] = (i == 1) and '[user]: ' .. line or line
	end
	vim.api.nvim_buf_set_lines(temp_history_bufnr, -1, -1, false, user_msg_lines)

	local response, err = config._prompt(chat_history)
	if err then
		vim.notify('ET.nvim: ' .. err, vim.log.levels.ERROR)
		return
	end

	table.insert(chat_history, { role = 'assistant', content = response })

	local response_lines = vim.split(response, '\n', { plain = true })
	for i, line in ipairs(response_lines) do
		response_lines[i] = (i == 1) and '[assistant]: ' .. line or line
	end
	vim.api.nvim_buf_set_lines(temp_history_bufnr, -1, -1, false, response_lines)
	vim.api.nvim_buf_set_lines(temp_history_bufnr, -1, -1, false, { '---' })

	vim.api.nvim_buf_set_lines(main_input_bufnr, 0, -1, false, {})

	return response
end

function M.add()
	-- add file_path / file_path#start_&_end_line
end

return M
