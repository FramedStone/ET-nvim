-- local agent = require('ET.agent')
local config = require('ET.config')
local popup = require('ET.ui')
local tools = require('ET.tools')

vim.api.nvim_create_user_command('ETSwitchModel', function()
	local models = config.get_models()

	local bufnr, win_id = popup.create_popup('Select Model', 50, #models)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, models)

	local function select_model()
		local cursor = vim.api.nvim_win_get_cursor(win_id)
		local selected = models[cursor[1]]
		local cfg = config.get_config()
		cfg.model = selected
		config.set_config(cfg)
		vim.api.nvim_win_close(win_id, true)
		vim.notify('ET.nvim: Switched to model ' .. selected)
	end

	vim.keymap.set('n', '<CR>', select_model, { buffer = bufnr, silent = true })
	vim.keymap.set('n', 'q', function()
		vim.api.nvim_win_close(win_id, true)
	end, { buffer = bufnr, silent = true })
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

vim.api.nvim_create_user_command('ETChat', function()
	-- TODO
	-- agent.open_chat()
end, { desc = 'Chat with ET' })

vim.api.nvim_create_user_command('ETInstallTools', function()
	tools.setup_external_tools()
end, { desc = 'Install External Tools' })
