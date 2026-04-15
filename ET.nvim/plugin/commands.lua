-- local agent = require('ET.agent')
local config = require('ET.config')

vim.api.nvim_create_user_command('ETChat', function()
	-- agent.start_mode('chat')
end, { desc = 'Open ET chat popup' })

vim.api.nvim_create_user_command('ETSwitchModel', function()
	-- agent.switch_model()
end, { desc = 'Switch ET model' })

vim.api.nvim_create_user_command('ETEditSettings', function()
	config.set_config()
end, { desc = 'Edit ET configuration' })
