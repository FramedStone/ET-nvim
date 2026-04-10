local M = {}

-- public API functions ET.setup({})
function M.setup(config)
	require('ET.config').set_config(config or {})
end

function M.init()
	require('ET.state').reset_state()
end

return M
