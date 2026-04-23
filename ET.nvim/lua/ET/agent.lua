local M = {}
local temp_history = {}
local config = require('ET.config')
local ui = require('ET.ui')

-- Set first model as default model
function M.init()
	local cfg = config.get_config()
	if cfg.model == vim.NIL then
		local models = config.get_models()
		if #models > 0 then
			cfg.model = models[1]
			config.set_config(cfg)
		else
			config.set_config()
		end
	end
end

function M.chat()
	-- main popup wrapping 2 popups (bravesearch, context7)
	-- if bravesearch or context7 has values --> seperate prompts into models
end
return M
