local M = {}
local chat_popup
local config = require('ET.config')
local ui = require('ET.ui')
local tools = require('ET.tools')

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

function M.open_chat()
	if not chat_popup then
		chat_popup = ui.create_popup('', 50, 10)
	end
	chat_popup:mount()
	vim.schedule(function()
		vim.api.nvim_set_current_win(chat_popup.winid)
	end)
end

function M.prompt() end

function M.add()
	-- add file_path / file_path#start_&_end_line
end

return M
