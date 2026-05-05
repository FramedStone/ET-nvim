local M = {}
local agent = require('ET.agent')

-- Use for public setup via setup({})
function M.setup()
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
