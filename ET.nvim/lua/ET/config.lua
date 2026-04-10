local M = {}

-- Default configuration
local default_config = {
	provider = 'omlx',
	omlx = {
		endpoint = 'http://localhost:8000/v1',
		api_key = '',
		model = nil,
	},
	sampling_params = {
		temperatur = nil,
		max_tokens = nil,
		top_p = nil,
		top_k = nil,
		repetition_penalty = nil,
		presence_penalty = nil,
		chat_template_kwargs = {
			enable_thinking = true,
			reasoning_effort = 'medium',
		},
	},
}

-- Config file path - in user's home directory under .et/
local config_path = vim.fn.stdpath('config') .. '/.et/config.json'

function M.save_config(user_config)
	local json_content = vim.fn.json_encode(user_config)
	vim.fn.writefile({ json_content }, config_path)
end

function M.load_config()
	local content
	local ok, err = pcall(function()
		content = vim.fn.readfile(config_path)
	end)
	if ok and content and type(content) == 'table' and #content > 0 then
		local merged = table.concat(content, '')
		return vim.fn.json_decode(merged) or {}
	end
	M.save_config(default_config)
	return default_config
end

function M.get_config()
	local user_config = M.load_config()
	return vim.tbl_deep_extend('force', {}, default_config, user_config)
end

function M.set_config(config)
	local user_config = M.load_config()
	user_config = vim.tbl_deep_extend('force', user_config, config or {})
	M.save_config(user_config)
end

function M.get_sampling_params()
	return M.get_config().sampling_params
end

function M.set_sampling_params(params)
	local user_config = M.load_config()
	user_config.sampling_params = vim.tbl_deep_extend('force', user_config.sampling_params or {}, params or {})
	M.save_config(user_config)
end

return M
