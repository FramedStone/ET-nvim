local M = {}

local config = require('ET.config')

local function normalize_model(value)
	local model = vim.trim(value or '')
	if vim.startswith(model, '● ') or vim.startswith(model, '○ ') then
		model = model:sub(5)
	end
	return vim.trim(model)
end

local function build_curl_cmd(method, endpoint, body)
	local url = config.get_config().omlx.endpoint .. endpoint
	local api_key = config.get_config().omlx.api_key
	local cmd = {
		'curl',
		'-s',
		'-X',
		method or 'POST',
		'-H',
		'Content-Type: application/json',
	}

	if api_key and api_key ~= '' then
		table.insert(cmd, '-H')
		table.insert(cmd, 'Authorization: Bearer ' .. api_key)
	end

	if body ~= nil then
		table.insert(cmd, '-d')
		table.insert(cmd, vim.fn.json_encode(body))
	end

	table.insert(cmd, url)
	return cmd
end

local function decode_response_or_error(response)
	local ok, decoded = pcall(vim.fn.json_decode, response)
	if not ok then
		if type(response) == 'string' and response:find('data:') then
			return response
		end
		error('Invalid JSON response from oMLX: ' .. tostring(response))
	end

	if decoded and decoded.error then
		local err = decoded.error
		error(err.message or vim.fn.json_encode(err))
	end

	return decoded
end

local function build_chat_body(prompt, messages)
	local model = normalize_model(config.get_config().omlx.model)
	if model == nil or model == '' then
		error('oMLX model is required. Configure ET with omlx.model before chatting.')
	end

	return {
		prompt = prompt,
		messages = messages,
		model = model,
		temperature = config.get_sampling_params().temperature,
		max_tokens = config.get_sampling_params().max_tokens,
		top_p = config.get_sampling_params().top_p,
		top_k = config.get_sampling_params().top_k,
		repetition_penalty = config.get_sampling_params().repetition_penalty,
		presence_penalty = config.get_sampling_params().presence_penalty,
		enable_thinking = config.get_sampling_params().chat_template_kwargs.enable_thinking,
		reasoning_effort = config.get_sampling_params().chat_template_kwargs.reasoning_effort,
	}
end

local function make_request(method, endpoint, body)
	local response = vim.fn.system(build_curl_cmd(method, endpoint, body))
	if vim.v.shell_error ~= 0 then
		error('Failed to send request: ' .. response)
	end
	return decode_response_or_error(response)
end

function M.complete(prompt, messages)
	local body = build_chat_body(prompt, messages)
	return make_request('POST', '/chat/completions', body)
end

function M.chat(messages)
	return M.complete(nil, messages)
end

function M.chat_async(messages, on_done)
	local ok, body_or_err = pcall(build_chat_body, nil, messages)
	if not ok then
		on_done(false, body_or_err)
		return
	end

	local cmd = build_curl_cmd('POST', '/chat/completions', body_or_err)
	vim.system(cmd, { text = true }, function(obj)
		vim.schedule(function()
			if obj.code ~= 0 then
				on_done(false, 'Failed to send request: ' .. (obj.stderr ~= '' and obj.stderr or obj.stdout or 'unknown error'))
				return
			end

			local ok_decode, decoded_or_err = pcall(decode_response_or_error, obj.stdout)
			if not ok_decode then
				on_done(false, decoded_or_err)
				return
			end

			on_done(true, decoded_or_err)
		end)
	end)
end

function M.list_models()
	local resp = make_request('GET', '/models', nil)
	if resp and resp.data and type(resp.data) == 'table' then
		local models = {}
		for _, item in ipairs(resp.data) do
			if type(item) == 'table' and item.id then
				table.insert(models, item.id)
			elseif type(item) == 'string' then
				table.insert(models, item)
			end
		end
		return models
	end

	if resp and resp.models and type(resp.models) == 'table' then
		local models = {}
		for _, item in ipairs(resp.models) do
			if type(item) == 'table' and item.id then
				table.insert(models, item.id)
			elseif type(item) == 'string' then
				table.insert(models, item)
			end
		end
		return models
	end

	return {}
end

return M
