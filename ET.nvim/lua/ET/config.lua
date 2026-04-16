local M = {}
local curl = require('plenary.curl')
local popup = require('ET.popup')
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

function M.set_config(new_config)
	local dir = vim.fn.fnamemodify(path, ':h')
	if vim.fn.isdirectory(dir) == 0 then
		vim.fn.mkdir(dir, 'p')
	end

	if new_config then
		local json = vim.fn.json_encode(new_config)
		vim.fn.writefile({ json }, path)
		if vim.fn.executable('fixjson') == 1 then
			vim.fn.system('fixjson --write ' .. path)
		end
		return
	end

	local cfg = M.get_config()

	if vim.fn.filereadable(path) == 0 then
		local json = vim.fn.json_encode(cfg)
		vim.fn.writefile({ json }, path)
		if vim.fn.executable('fixjson') == 1 then
			vim.fn.system('fixjson --write ' .. path)
		end
	end

	local bufnr, win_id = popup.create_popup('Edit Settings', 60, 20)
	vim.api.nvim_win_call(win_id, function()
		vim.cmd('edit ' .. path)
		vim.bo.filetype = 'json'
	end)
end

function M.get_models()
	local cfg = M.get_config()
	local url = cfg.endpoint .. '/models'
	if cfg.api_key ~= '' then
		url = url .. '?api_key=' .. cfg.api_key
	end

	local response = curl.get(url, {
		timeout = 1000,
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

return M
