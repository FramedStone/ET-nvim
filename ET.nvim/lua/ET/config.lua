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
		temperature = nil,
		max_tokens = nil,
		top_p = nil,
		top_k = nil,
		repetition_penalty = nil,
		presence_penalty = nil,
		chat_template_kwargs = {
			enable_thinking = nil,
			reasoning_effort = nil,
		},
	},
}

-- Save schema (preserves null fields in JSON)
local save_schema = {
	provider = 'omlx',
	omlx = {
		endpoint = 'http://localhost:8000/v1',
		api_key = '',
		model = vim.NIL,
	},
	sampling_params = {
		temperature = vim.NIL,
		max_tokens = vim.NIL,
		top_p = vim.NIL,
		top_k = vim.NIL,
		repetition_penalty = vim.NIL,
		presence_penalty = vim.NIL,
		chat_template_kwargs = {
			enable_thinking = vim.NIL,
			reasoning_effort = vim.NIL,
		},
	},
}

local function encode_json_value(value)
	if value == vim.NIL or value == nil then
		return 'null'
	end
	return vim.fn.json_encode(value)
end

local function to_pretty_config_json(cfg)
	local omlx = cfg.omlx or {}
	local sampling = cfg.sampling_params or {}
	local chat_kwargs = sampling.chat_template_kwargs or {}

	return table.concat({
		'{',
		'  "provider": ' .. encode_json_value(cfg.provider) .. ',',
		'  "omlx": {',
		'    "endpoint": ' .. encode_json_value(omlx.endpoint) .. ',',
		'    "api_key": ' .. encode_json_value(omlx.api_key) .. ',',
		'    "model": ' .. encode_json_value(omlx.model),
		'  },',
		'  "sampling_params": {',
		'    "temperature": ' .. encode_json_value(sampling.temperature) .. ',',
		'    "max_tokens": ' .. encode_json_value(sampling.max_tokens) .. ',',
		'    "top_p": ' .. encode_json_value(sampling.top_p) .. ',',
		'    "top_k": ' .. encode_json_value(sampling.top_k) .. ',',
		'    "repetition_penalty": ' .. encode_json_value(sampling.repetition_penalty) .. ',',
		'    "presence_penalty": ' .. encode_json_value(sampling.presence_penalty) .. ',',
		'    "chat_template_kwargs": {',
		'      "enable_thinking": ' .. encode_json_value(chat_kwargs.enable_thinking) .. ',',
		'      "reasoning_effort": ' .. encode_json_value(chat_kwargs.reasoning_effort),
		'    }',
		'  }',
		'}',
	}, '\n')
end

local function normalize_for_save(user, schema)
	user = type(user) == 'table' and user or {}
	local result = {}

	for key, schema_val in pairs(schema or {}) do
		local user_val = user[key]
		if type(schema_val) == 'table' then
			result[key] = normalize_for_save(type(user_val) == 'table' and user_val or {}, schema_val)
		elseif user_val == nil then
			result[key] = schema_val
		else
			result[key] = user_val
		end
	end

	for key, user_val in pairs(user) do
		if result[key] == nil then
			result[key] = user_val
		end
	end

	return result
end

-- Config file path - in user's home directory under .et/
local config_path = vim.fn.stdpath('config') .. '/.et/config.json'

function M.save_config(user_config)
	local normalized = normalize_for_save(user_config, save_schema)
	local json_content = to_pretty_config_json(normalized)
	vim.fn.writefile(vim.split(json_content, '\n', { plain = true }), config_path)
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
	local sampling_params = M.get_config().sampling_params or {}
	if sampling_params.temperature == nil and sampling_params.temperatur ~= nil then
		sampling_params.temperature = sampling_params.temperatur
	end

	if sampling_params.chat_template_kwargs == nil then
		sampling_params.chat_template_kwargs = {
			enable_thinking = nil,
			reasoning_effort = nil,
		}
	end

	return sampling_params
end

function M.set_sampling_params(params)
	local user_config = M.load_config()
	user_config.sampling_params = vim.tbl_deep_extend('force', user_config.sampling_params or {}, params or {})
	M.save_config(user_config)
end

return M
