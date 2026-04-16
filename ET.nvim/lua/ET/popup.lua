local M = {}
local popup = require('plenary.popup')

-- TODO: expose a callback to close the popup state properly
function M.create_popup(title, width, height)
	width = math.max(width or 50)
	height = math.max(height or 1)

	local bufnr = vim.api.nvim_create_buf(false, true)
	local win_id, opts = popup.create(bufnr, {
		title = title,
		line = math.floor(((vim.o.lines - height) / 2) - 1),
		col = math.floor((vim.o.columns - width) / 2),
		minwidth = width,
		minheight = height,
		border = true,
	})

	return bufnr, win_id
end

return M
