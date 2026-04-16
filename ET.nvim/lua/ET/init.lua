local M = {}

-- Use for public setup via setup({})
function M.setup(opts)
	local bx = vim.fn.executable('bx')
	local ctx7 = vim.fn.executable('ctx7')
	if bx == 0 or ctx7 == 0 then
		vim.notify(string.rep('=', 25) .. 'ET.nvim' .. string.rep('=', 25))
		if bx == 0 then
			vim.notify('- bx not installed (bravesearch cli)')
		end
		if ctx7 == 0 then
			vim.notify('- ctx7 not installed (context7 cli)')
		end
		vim.notify('\n\nRun :ETInstallTools to install all external tools')
		vim.notify(string.rep('=', 57))
	end
end

return M
