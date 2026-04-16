local config = require('ET.config')

vim.api.nvim_create_autocmd('VimEnter', {
	-- Onboard if config.json not found
	-- Select first model returned from oMLX endpoint as default
	group = vim.api.nvim_create_augroup('ETOnboard', { clear = true }),
	callback = function()
		local path = vim.fn.stdpath('config') .. '/.et/config.json'
		if vim.fn.filereadable(path) == 0 then
			config.set_config()
		else
			local cfg = config.get_config()
			if cfg.model == vim.NIL or cfg.model == '' then
				local models = config.get_models()
				if #models > 0 then
					cfg.model = models[1]
					-- Write back to config file
					local dir = vim.fn.fnamemodify(path, ':h')
					if vim.fn.isdirectory(dir) == 0 then
						vim.fn.mkdir(dir, 'p')
					end
					local json = vim.fn.json_encode(cfg)
					vim.fn.writefile({ json }, path)
				end
			end
		end
	end,
})
