local M = {}
local ui = require('ET.ui')
local path = vim.fn.stdpath('config') .. '/.et/config.json'
local config = {
	endpoint = 'http://localhost:8000/v1',
	api_key = '',
	model = vim.NIL,
	sampling_params = {
		temperature = vim.NIL,
		max_tokens = vim.NIL,
		top_p = vim.NIL,
		top_k = vim.NIL,
		repetition_penalty = vim.NIL,
		presence_penalty = vim.NIL,
		chat_template_kwargs = {
			enable_thinking = true,
			reasoning_effort = vim.NIL,
		},
	},
	system_prompt = 'You are an agent that acts only through tools. You must respond only with a JSON tool call, with no text before or after.',
}

function M.get_config()
	if vim.fn.filereadable(path) == 1 then
		local content = vim.fn.readfile(path)
		local ok, decoded = pcall(vim.fn.json_decode, table.concat(content, ''))
		if ok then
			return vim.tbl_deep_extend('force', config, decoded)
		end
	end
	return config
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

function M.get_models()
	local cfg = M.get_config()
	local url = cfg.endpoint .. '/models'
	if cfg.api_key ~= '' then
		url = url .. '?api_key=' .. cfg.api_key
	end

	local cmd = string.format('curl -s -H "Authorization: Bearer %s" -H "Content-Type: application/json" %s',
		cfg.api_key, vim.fn.shellescape(url))
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

function M._prompt(messages, on_tool_call, on_done, opts)
	opts = opts or {}
	local cfg = M.get_config()
	local url = cfg.endpoint .. '/chat/completions'

	local payload = {
		model = cfg.model,
		messages = messages,
		stream = true,
	}

	if opts.tools then
		payload.tools = opts.tools
	end

	if cfg.sampling_params then
		payload = vim.tbl_deep_extend('force', payload, cfg.sampling_params)
	end

	local cmd = {
		'curl', '-s', '-N', '-X', 'POST',
		'-H', 'Content-Type: application/json',
	}
	if cfg.api_key and cfg.api_key ~= '' then
		table.insert(cmd, '-H')
		table.insert(cmd, 'Authorization: Bearer ' .. cfg.api_key)
	end
	table.insert(cmd, '-d')
	table.insert(cmd, vim.fn.json_encode(payload))
	table.insert(cmd, url)

	local full_content = {}
	local tool_calls = {}
	local state = 'streaming' -- 'streaming' | 'done'

	-- Merge a streaming delta chunk into the accumulated tool_calls array
	local function accumulate_tool_call(tc)
		local idx = tc.index + 1
		if not tool_calls[idx] then
			tool_calls[idx] = {
				id = tc.id or '',
				type = tc.type or 'function',
				['function'] = {
					name = tc['function'] and tc['function'].name or '',
					arguments = '',
				},
			}
		end
		if tc.id and tc.id ~= '' then
			tool_calls[idx].id = tc.id
		end
		if tc['function'] and tc['function'].name and tc['function'].name ~= '' then
			tool_calls[idx]['function'].name = tc['function'].name
		end
		if tc['function'] and tc['function'].arguments then
			tool_calls[idx]['function'].arguments = tool_calls[idx]['function'].arguments .. tc['function'].arguments
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

			if choice.finish_reason == 'tool_calls' then
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
