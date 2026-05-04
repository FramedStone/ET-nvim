local M = {}

local config = require('ET.config')

-- Persistent per-project (saved to ~/.config/nvim/.et/states/<hash>.json)
M._system_prompt_additions = {}

-- One-shot, cleared after prompt() call
M._current_prompt_context = {}

-- Tool results
M.bravesearch = { results = {}, selected_type = 'web' }
M.context7 = {
	library_results = {},
	docs_code_snippets = {},
	docs_info_snippets = {},
}

-- UI references
M.ui = {
	chat_popup = nil,
	chat_buffer_lines = {},
	library_result_tree = nil,
	docs_result_tree = nil,
	docs_library_input = nil,
	docs_input = nil,
	bravesearch_result_tree = nil,
	bravesearch_result_popup = nil,
}

-- Staged edits pending review
M.pending_edits = {}

-- Persistence helpers
local function get_project_hash()
	local cwd = vim.fn.getcwd()
	local hash = 0
	for i = 1, #cwd do
		hash = (hash * 31 + string.byte(cwd, i)) % 2147483647
	end
	return tostring(hash)
end

local function get_states_dir()
	local dir = vim.fn.stdpath('config') .. '/.et/states'
	if vim.fn.isdirectory(dir) == 0 then
		vim.fn.mkdir(dir, 'p')
	end
	return dir
end

local function get_state_path()
	return get_states_dir() .. '/' .. get_project_hash() .. '.json'
end

function M.save()
	local path = get_state_path()
	local data = {
		system_prompt_additions = M._system_prompt_additions,
	}
	local json = vim.fn.json_encode(data)
	vim.fn.writefile({ json }, path)
end

function M.load()
	local path = get_state_path()
	if vim.fn.filereadable(path) == 1 then
		local content = vim.fn.readfile(path)
		local ok, decoded = pcall(vim.fn.json_decode, table.concat(content, ''))
		if ok and decoded then
			M._system_prompt_additions = decoded.system_prompt_additions or {}
		end
	end
end

-- System prompt
function M.add_to_system_prompt(text)
	table.insert(M._system_prompt_additions, text)
	M.save()
end

function M.get_system_prompt()
	local cfg = config.get_config()
	local base = cfg.system_prompt or ''
	if #M._system_prompt_additions == 0 then
		return base
	end
	local additions = table.concat(M._system_prompt_additions, '\n\n')
	return base .. '\n\n' .. additions
end

-- Current prompt context (one-shot)
function M.add_to_prompt(text)
	table.insert(M._current_prompt_context, text)
end

function M.get_prompt_context()
	if #M._current_prompt_context == 0 then
		return ''
	end
	local context = table.concat(M._current_prompt_context, '\n\n')
	M._current_prompt_context = {}
	return context
end

-- Tool results
function M.set_bravesearch_results(results)
	M.bravesearch.results = results or {}
end

function M.set_context7_docs(code_snippets, info_snippets)
	M.context7.docs_code_snippets = code_snippets or {}
	M.context7.docs_info_snippets = info_snippets or {}
end

-- Initialize: load persisted state
M.load()

return M
