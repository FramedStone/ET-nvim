local M = {}
local ui = require('ET.ui')

-- Provider definitions with per-provider defaults and capabilities.
local providers = {
	['llama.cpp'] = {
		default_endpoint = 'http://localhost:8080/v1',
		default_model = vim.NIL,
		description = 'llama.cpp via llama-server',
		supports_api_key = false,
		-- thinking mode is configured via sampling_params.chat_template_kwargs
		-- tool calls: both OpenAI nested {function:{name, arguments}} and
		--            llama.cpp flat {name, arguments}
		-- finish_reason: "tool_calls" (OpenAI compat) or "tool" (llama.cpp legacy)
	},
	['ds4'] = {
		default_endpoint = 'http://127.0.0.1:8000/v1',
		default_model = 'deepseek-v4-flash',
		description = 'ds4.c local inference engine for DeepSeek V4 Flash',
		supports_api_key = true,
		-- thinking mode uses body fields: thinking, reasoning_effort
		-- tool calls: standard OpenAI format only
		-- finish_reason: "tool_calls" only
	},
}

local path = vim.fn.stdpath('config') .. '/.et/config.json'
local config = {
	provider = 'llama.cpp',
	endpoint = 'http://localhost:8080/v1',
	model = vim.NIL,
	api_key = vim.NIL,
	reasoning_effort = vim.NIL,
	sampling_params = {
		temperature = vim.NIL,
		max_tokens = vim.NIL,
		top_p = vim.NIL,
		top_k = vim.NIL,
		repetition_penalty = vim.NIL,
		presence_penalty = vim.NIL,
		chat_template_kwargs = {
			enable_thinking = vim.NIL,
			thinking_budget = vim.NIL,
		},
	},
	system_prompt = 'You are an AI coding assistant that modifies code using available tools.',
}

--- Get the active provider's capability table.
--- @return table provider config
function M.get_provider()
	local cfg = M.get_config()
	return providers[cfg.provider] or providers['llama.cpp']
end

--- List all known provider IDs with their metadata.
--- @return table[] {id, description, default_endpoint, default_model}[]
function M.get_providers()
	local items = {}
	for id, prov in pairs(providers) do
		table.insert(items, {
			id = id,
			description = prov.description,
			default_endpoint = prov.default_endpoint,
			default_model = prov.default_model,
		})
	end
	table.sort(items, function(a, b) return a.id < b.id end)
	return items
end

--- Get a provider's metadata by ID.
--- @param id string
--- @return table|nil
function M.get_provider_info(id)
	return providers[id]
end

--- Deep-merge user config on top of defaults.
--- When switching providers, apply that provider's default endpoint and model
--- if the user hasn't explicitly set them.
function M.get_config()
	local cfg
	if vim.fn.filereadable(path) == 1 then
		local content = vim.fn.readfile(path)
		local ok, decoded = pcall(vim.fn.json_decode, table.concat(content, ''))
		if ok then
			cfg = vim.tbl_deep_extend('force', vim.deepcopy(config), decoded)
		end
	end
	cfg = cfg or vim.deepcopy(config)

	-- Apply provider defaults for unset fields
	local prov = providers[cfg.provider]
	if prov then
		if cfg.endpoint == vim.NIL or cfg.endpoint == config.endpoint then
			cfg.endpoint = prov.default_endpoint
		end
		if cfg.model == vim.NIL then
			cfg.model = prov.default_model
		end
	end

	return cfg
end

local function ensure_dir()
	local dir = vim.fn.stdpath('config') .. '/.et'
	if vim.fn.isdirectory(dir) == 0 then
		vim.fn.mkdir(dir, 'p')
	end
end

function M.save_config(cfg)
	ensure_dir()
	local json = vim.fn.json_encode(cfg)
	vim.fn.writefile({ json }, path)
	vim.fn.system('fixjson --write ' .. path)
end

function M.edit_config_ui()
	local current = M.get_config()
	local current_json = vim.fn.json_encode(current)
	local temp = '/tmp/et_config_temp.json'
	vim.fn.writefile({ current_json }, temp)
	vim.fn.system('fixjson --write "' .. temp .. '"')
	local formatted = vim.fn.readfile(temp)
	local height = #formatted

	local p = ui.create_popup('Edit Settings', '60%', height)
	vim.api.nvim_buf_set_lines(p.bufnr, 0, -1, false, formatted)
	vim.api.nvim_buf_set_option(p.bufnr, 'relativenumber', true)

	ui.bind_save_close_keys(p, function()
		local lines = vim.api.nvim_buf_get_lines(p.bufnr, 0, -1, false)
		local content = table.concat(lines, '\n')
		local ok, decoded = pcall(vim.fn.json_decode, content)
		if ok then
			M.save_config(decoded)
		else
			vim.notify('ET.nvim: Invalid JSON', vim.log.levels.ERROR)
		end
		p:unmount()
	end)
end

--- Fetch available models from the provider's /v1/models endpoint.
--- Includes API key header for providers that need it.
function M.get_models()
	local cfg = M.get_config()
	local prov = M.get_provider()
	local url = cfg.endpoint .. '/models'

	local headers = { 'Content-Type: application/json' }
	if prov.supports_api_key and cfg.api_key and cfg.api_key ~= vim.NIL then
		table.insert(headers, 'Authorization: Bearer ' .. cfg.api_key)
	end

	local header_args = {}
	for _, h in ipairs(headers) do
		table.insert(header_args, '-H')
		table.insert(header_args, vim.fn.shellescape(h))
	end

	local cmd = 'curl -s ' .. table.concat(header_args, ' ') .. ' ' .. vim.fn.shellescape(url)
	local result = vim.fn.system(cmd)

	if vim.v.shell_error ~= 0 then
		vim.notify('ET.nvim: Failed to fetch models from ' .. cfg.endpoint, vim.log.levels.ERROR)
		return {}
	end

	local ok, decoded = pcall(vim.fn.json_decode, result)
	if not ok or not decoded.data then
		vim.notify('ET.nvim: Failed to parse models response', vim.log.levels.ERROR)
		return {}
	end

	local models = {}
	for _, model in ipairs(decoded.data) do
		table.insert(models, model.id)
	end
	return models
end

--- Build the curl command and headers for a chat/completions request.
--- Provider-specific differences are handled here:
---   - API key header (ds4)
---   - Thinking mode payload: llama.cpp uses chat_template_kwargs,
---     ds4 uses thinking + reasoning_effort
local function build_request(cfg, payload)
	local prov = M.get_provider()
	local url = cfg.endpoint .. '/chat/completions'

	local headers = { 'Content-Type: application/json' }
	if prov.supports_api_key and cfg.api_key and cfg.api_key ~= vim.NIL then
		table.insert(headers, 'Authorization: Bearer ' .. cfg.api_key)
	end

	-- Build provider-specific payload additions
	local body = vim.deepcopy(payload)

	---@diagnostic disable-next-line: cast-local-type
	body.stream = true

	-- Merge sampling_params into body (this includes temperature, max_tokens, etc.)
	-- nil fields are stripped in the loop below
	if cfg.sampling_params then
		body = vim.tbl_deep_extend('force', body, cfg.sampling_params)
	end

	-- Provider-specific thinking mode handling
	if cfg.provider == 'ds4' then
		-- ds4 uses thinking + reasoning_effort, NOT chat_template_kwargs
		body.chat_template_kwargs = nil
		if cfg.reasoning_effort and cfg.reasoning_effort ~= vim.NIL then
			body.reasoning_effort = cfg.reasoning_effort
		end
		-- If the user hasn't explicitly disabled thinking, enable it by default
		if body.thinking == nil then
			body.thinking = { type = 'enabled' }
		end
	else
		-- llama.cpp: keep chat_template_kwargs, remove thinking/reasoning_effort
		body.thinking = nil
		body.reasoning_effort = nil
	end

	-- Strip nil fields so the server gets clean JSON
	local cleaned = {}
	for k, v in pairs(body) do
		if v ~= vim.NIL then
			cleaned[k] = v
		end
	end

	-- Build curl command
	local curl_args = { 'curl', '-s', '-N', '-X', 'POST' }
	for _, h in ipairs(headers) do
		table.insert(curl_args, '-H')
		table.insert(curl_args, h)
	end
	table.insert(curl_args, '-d')
	table.insert(curl_args, vim.fn.json_encode(cleaned))
	table.insert(curl_args, url)

	return curl_args
end

function M._prompt(messages, on_tool_call, on_done, opts)
	opts = opts or {}
	local cfg = M.get_config()

	local payload = {
		model = cfg.model,
		messages = messages,
	}

	if opts.tools then
		payload.tools = opts.tools
	end

	local cmd = build_request(cfg, payload)

	local full_content = {}
	local tool_calls = {}
	local state = 'streaming' -- 'streaming' | 'done'

	-- Merge a streaming delta chunk into the accumulated tool_calls array.
	-- Handles both OpenAI nested format {function: {name, arguments}}
	-- and llama.cpp flat format {name, arguments}.
	local function accumulate_tool_call(tc)
		local idx = tc.index + 1
		local fn = tc['function'] or tc
		if not tool_calls[idx] then
			tool_calls[idx] = {
				id = tc.id or '',
				type = tc.type or 'function',
				['function'] = {
					name = fn.name or '',
					arguments = '',
				},
			}
		end
		if tc.id and tc.id ~= '' then
			tool_calls[idx].id = tc.id
		end
		if fn.name and fn.name ~= '' then
			tool_calls[idx]['function'].name = fn.name
		end
		if fn.arguments then
			tool_calls[idx]['function'].arguments = tool_calls[idx]['function'].arguments .. fn.arguments
		end
	end

	local function on_stdout(_, data)
		if not data then return end
		for _, line in ipairs(data) do
			if not line:find('^data: ') then goto continue end
			local json_str = line:sub(7)
			if json_str == '[DONE]' then goto continue end

			local ok, decoded = pcall(vim.fn.json_decode, json_str)
			if not (ok and decoded.choices and decoded.choices[1]) then goto continue end

			local choice = decoded.choices[1]
			local delta = choice.delta
			if not delta then goto continue end

			if delta.content then
				table.insert(full_content, delta.content)
			end

			if delta.tool_calls then
				for _, tc in ipairs(delta.tool_calls) do
					accumulate_tool_call(tc)
				end
			end

			-- Both providers use "tool_calls"; llama.cpp also sends "tool"
			if choice.finish_reason == 'tool_calls' or choice.finish_reason == 'tool' then
				on_tool_call(tool_calls)
				tool_calls = {}
				state = 'done'
				return
			elseif choice.finish_reason == 'stop' then
				on_done(table.concat(full_content))
				state = 'done'
				return
			end

			::continue::
		end
	end

	local function on_exit()
		if state ~= 'done' then
			on_done(table.concat(full_content))
		end
	end

	vim.fn.jobstart(cmd, {
		on_stdout = on_stdout,
		on_exit = on_exit,
		stdout_buffered = false,
	})
end

return M
