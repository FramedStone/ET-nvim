local agent = require('ET.agent')
local config = require('ET.config')
local popup = require('ET.ui')
local tools = require('ET.tools')

vim.api.nvim_create_user_command('ETSwitchModel', function()
	local models = config.get_models()

	local model_items = {}
	for _, model in ipairs(models) do
		table.insert(model_items, { text = model })
	end

	popup.create_menu('Select Model', model_items, function(selected)
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
	-- TODO
	-- agent.init()
	-- agent.open_chat()
	-- agent.insert_into_popup(object)
end, { range = true, desc = 'Parse Highlighted Line of Codes into ETAgent' })

vim.api.nvim_create_user_command('ETBraveSearch', function() end, { desc = '' })

vim.api.nvim_create_user_command('ETContext7', function() end, { desc = '' })

vim.api.nvim_create_user_command('ETInstallTools', function()
	tools.setup_external_tools()
end, { desc = 'Install External Tools' })
