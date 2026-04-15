local M = {}
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
		local ok, decoded = pcall(vim.fn.json_decode, table.concat(content, ""))
		if ok then
			return vim.tbl_deep_extend("force", config, decoded)
		end
	end
	return config
end

function M.set_config()
	local dir = vim.fn.fnamemodify(path, ':h')
	if vim.fn.isdirectory(dir) == 0 then
		vim.fn.mkdir(dir, 'p')
	end

	if vim.fn.filereadable(path) == 0 then
		local json = vim.fn.json_encode(config)
		vim.fn.writefile({ json }, path)

		-- Beautify config.json with fixjson if available
		if vim.fn.executable('fixjson') == 1 then
			vim.fn.system('fixjson --write ' .. path)
		end
	end

	vim.cmd('edit ' .. path)
end

return M
