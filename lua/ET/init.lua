local M = {}
local config = require('ET.config')
local agent = require('ET.agent')

-- Public setup. Accepts an opts table that deep-merges into config.json.
--
-- Usage via lazy.nvim:
--   opts = { endpoint = 'http://localhost:8000/v1', model = 'llama3' }
--
-- Or explicit config function:
--   config = function()
--     require('ET').setup({ api_key = 'sk-...' })
--   end
function M.setup(opts)
	-- Merge user opts into config (saves to disk so :ETEditSettings stays in sync)
	if opts and type(opts) == 'table' then
		local cfg = config.get_config()
		cfg = vim.tbl_deep_extend('force', cfg, opts)
		config.save_config(cfg)
	end

	-- Check external tool dependencies
	local missing = {}
	if vim.fn.executable('bx') == 0 then
		table.insert(missing, 'bx (bravesearch cli)')
	end
	if vim.fn.executable('ctx7') == 0 then
		table.insert(missing, 'ctx7 (context7 cli)')
	end
	if vim.fn.executable('jq') == 0 then
		table.insert(missing, 'jq (json processor)')
	end
	if vim.fn.executable('lynx') == 0 then
		table.insert(missing, 'lynx (html-to-text for web_fetch)')
	end

	if #missing > 0 then
		vim.notify(string.rep('=', 20) .. ' ET.nvim ' .. string.rep('=', 20))
		for _, tool in ipairs(missing) do
			vim.notify('  missing: ' .. tool)
		end
		vim.notify('\nRun :ETInstallTools to install all external tools')
		vim.notify(string.rep('=', 51))
	end

	agent.init()
end

return M
