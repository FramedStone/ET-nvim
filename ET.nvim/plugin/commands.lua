local agent = require('ET.agent')
local config = require('ET.config')

vim.api.nvim_create_user_command('ETChat', function()
	agent.start_mode('chat')
end, { desc = 'Open ET chat popup' })

vim.api.nvim_create_user_command('ETAgent', function()
	agent.start_mode('agent')
end, { desc = 'Open ET agent popup' })

vim.api.nvim_create_user_command('ETSwitchModel', function()
	agent.switch_model()
end, { desc = 'Switch ET model' })

vim.api.nvim_create_user_command('ETFilePicker', function()
	agent.file_picker()
end, { desc = 'Open ET file/range picker and append references' })

vim.api.nvim_create_user_command('ETEditSettings', function()
	local settings_path = vim.fn.stdpath('config') .. '/.et/config.json'
	if vim.fn.filereadable(settings_path) == 0 then
		config.save_config(config.get_config())
	end

	vim.cmd('edit ' .. vim.fn.fnameescape(settings_path))
end, { desc = 'Edit ET settings config.json' })
