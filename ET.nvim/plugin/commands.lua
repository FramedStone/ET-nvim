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
		local cfg = config.get_config()
		cfg.model = selected
		config.set_config(cfg)
		vim.notify('ET.nvim: Switched to model ' .. selected)
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
	local search_popup = Popup({
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

	local search_input = Popup({
		border = {
			style = 'rounded',
			text = {
				top = '[Search Input]',
			},
		},
		buf_options = {
			buftype = '',
			modifiable = true,
			readonly = false,
		},
	})

	local type_menu = Menu({
		border = {
			style = 'rounded',
			text = {
				top = '[Type]',
			},
		},
	}, {
		lines = {
			Menu.item('web'),
			Menu.item('news'),
			Menu.item('images'),
			Menu.item('videos'),
		},
		keymap = {
			focus_next = { 'j', '<Down>' },
			focus_prev = { 'k', '<Up>' },
		},
		on_submit = function(item)
			vim.notify('Selected: ' .. item.text)
		end,
	})

	ui.create_layout(70, 30, {
		{ component = search_popup, size = 80 },
		{
			dir = 'row',
			size = 20,
			{ component = search_input, size = 60, initial_focus = true },
			{ component = type_menu, size = 40 },
		},
	}, 'col')
end, { desc = 'Brave Search' })

vim.api.nvim_create_user_command('ETContext7', function()
	ui.create_menu('Context7', {
		{ text = 'library' },
		{ text = 'docs' },
	}, function(selected)
		if selected == 'library' then
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
		elseif selected == 'docs' then
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
