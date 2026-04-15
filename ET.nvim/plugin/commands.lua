local agent = require('ET.agent')

vim.api.nvim_create_user_command('ETChat', function()
	-- agent.start_mode('chat')
end, { desc = 'Open ET chat popup' })

vim.api.nvim_create_user_command('ETSwitchModel', function()
	-- agent.switch_model()
end, { desc = 'Switch ET model' })
