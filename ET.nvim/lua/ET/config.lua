local M = {}
local curl = require('plenary.curl')
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

function M.set_config(cfg)
	if cfg then
		if vim.fn.filereadable(path) == 0 then
			local dir = vim.fn.stdpath('config') .. '/.et'
			if vim.fn.isdirectory(dir) == 0 then
				vim.fn.mkdir(dir, 'p')
			end
		end
		local json = vim.fn.json_encode(cfg)
		vim.fn.writefile({ json }, path)
		vim.fn.system('fixjson --write ' .. path)
		return
	end

	local current = M.get_config()
	local current_json = vim.fn.json_encode(current)
	local temp = '/tmp/et_config_temp.json'
	vim.fn.writefile({ current_json }, temp)
	vim.fn.system('fixjson --write "' .. temp .. '"')
	local formatted = vim.fn.readfile(temp)
	local height = #formatted

	local p = ui.create_popup('Edit Settings', 60, height)

	vim.api.nvim_buf_set_lines(p.bufnr, 0, -1, false, formatted)

	vim.api.nvim_buf_set_option(p.bufnr, 'relativenumber', true)

	local function save_and_close()
		local lines = vim.api.nvim_buf_get_lines(p.bufnr, 0, -1, false)
		local content = table.concat(lines, '\n')
		local ok, decoded = pcall(vim.fn.json_decode, content)
		if ok then
			M.set_config(decoded)
		else
			vim.notify('ET.nvim: Invalid JSON', vim.log.levels.ERROR)
		end
	end

	local function close_popup()
		p:unmount()
	end

	p:map('n', ':wq<CR>', function()
		save_and_close()
		p:unmount()
	end, { noremap = true })
	p:map('n', 'q', close_popup, { noremap = true })
end

function M.get_models()
	local cfg = M.get_config()
	local url = cfg.endpoint .. '/models'
	if cfg.api_key ~= '' then
		url = url .. '?api_key=' .. cfg.api_key
	end

	local response = curl.get(url, {
		timeout = 10000,
		headers = {
			Authorization = 'Bearer ' .. cfg.api_key,
			['Content-Type'] = 'application/json',
		},
	})

	if response.status ~= 200 then
		vim.notify('ET.nvim: Failed to fetch models from ' .. cfg.endpoint, vim.log.levels.ERROR)
		return {}
	end

	local ok, decoded = pcall(vim.fn.json_decode, response.body)
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

function M._prompt(contents, on_chunk, on_done)
	local cfg = M.get_config()
	local url = cfg.endpoint .. '/chat/completions'

	local messages = {}
	if type(contents) == 'string' then
		table.insert(messages, { role = 'user', content = contents })
	elseif type(contents) == 'table' then
		messages = contents
	end

	if cfg.system_prompt and cfg.system_prompt ~= '' then
		table.insert(messages, 1, { role = 'system', content = cfg.system_prompt })
	end

	local payload = {
		model = cfg.model,
		messages = messages,
		stream = true,
	}

	if cfg.sampling_params then
		payload = vim.tbl_deep_extend('force', payload, cfg.sampling_params)
	end

	local cmd = {
		'curl',
		'-s',
		'-N',
		'-X',
		'POST',
		'-H',
		'Content-Type: application/json',
	}
	if cfg.api_key and cfg.api_key ~= '' then
		table.insert(cmd, '-H')
		table.insert(cmd, 'Authorization: Bearer ' .. cfg.api_key)
	end
	table.insert(cmd, '-d')
	table.insert(cmd, vim.fn.json_encode(payload))
	table.insert(cmd, url)

	local full_content = {}

	local function on_stdout(_, data)
		if data and #data > 0 then
			for _, line in ipairs(data) do
				if line:find('^data: ') then
					local json_str = line:sub(7)
					if json_str ~= '[DONE]' then
						local ok, decoded = pcall(vim.fn.json_decode, json_str)
						if ok and decoded.choices and decoded.choices[1] and decoded.choices[1].delta then
							local content = decoded.choices[1].delta.content
							if content then
								table.insert(full_content, content)
								if on_chunk then
									on_chunk(content)
								end
							end
						end
					end
				end
			end
		end
	end

	local function on_exit(_, code)
		if on_done then
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
