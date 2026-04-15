local M = {}
local state = require('ET.state')

function M.setup()
	print('ET.nvim loaded')
end

function M.init()
	state.reset_state()
end

return M
