local M = {}
local chat_ui
local chat_components
local temp_history = {}
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
	local Input = require('nui.input')
	local temp_history = Popup({
		border = {
			style = 'rounded',
			text = {
				top = 'Temp History',
				top_align = 'center',
			},
		},
	})

	local main_input = Input({
		position = '50%',
		size = { width = 40 },
		border = {
			style = 'rounded',
			text = {
				top = '[Input]',
				top_align = 'center',
			},
		},
	}, {
		on_submit = function(value)
			-- TODO
			print('Input submitted: ' .. value)
		end,
	})

	local brave_input = Input({
		position = '50%',
		size = { width = 40 },
		border = {
			style = 'rounded',
			text = {
				top = 'Brave Search',
			},
		},
	}, {
		on_submit = function(value)
			-- TODO
			print('Brave Search: ' .. value)
		end,
	})

	local context_input = Input({
		position = '50%',
		size = { width = 40 },
		border = {
			style = 'rounded',
			text = {
				top = 'Context7',
			},
		},
	}, {
		on_submit = function(value)
			-- TODO
			print('Context7: ' .. value)
		end,
	})

	chat_components = {
		temp_history = temp_history,
		main_input = main_input,
		brave_input = brave_input,
		context_input = context_input,
	}

	chat_ui = ui.create_layout(100, 40, {
		{ dir = 'col', size = 50, { component = temp_history, size = 90 }, { component = main_input, size = 10 } },
		{ dir = 'col', size = 50, { component = brave_input, size = 50 }, { component = context_input, size = 50 } },
	}, 'row')
	vim.schedule(function()
		chat_ui:hide()
	end)
end

function M.open_chat()
	chat_ui:show()
	vim.schedule(function()
		if chat_components and chat_components.main_input then
			vim.api.nvim_set_current_win(chat_components.main_input.winid)
		end
	end)
end

function M.prompt()
	-- main popup wrapping 2 popups (bravesearch, context7)
	-- if bravesearch or context7 has values --> seperate prompts into models
	-- cherry picking flow after bravesearch/context7 tools result
	-- pr flow after using edit/write tools
end

function M.add()
	-- add file_path / file_path#start_&_end_line
end

return M
