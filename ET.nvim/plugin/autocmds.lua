local config = require('ET.config')

vim.api.nvim_create_autocmd('VimEnter', {
	group = vim.api.nvim_create_augroup('ETOnboard', { clear = true }),
	callback = function()
		local path = vim.fn.stdpath('config') .. '/.et/config.json'
		if vim.fn.filereadable(path) == 0 then
			config.set_config()
		else
			config.get_config()
		end
	end,
})
