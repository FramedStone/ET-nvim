local M = {}
local fzf = require('fzf-lua')

function M.select_files()
	fzf.files({
		actions = {
			['default'] = function(selected)
				-- Extract the path (strips icons/formatting)
				local file = fzf.path.entry_to_file(selected[1])
				-- TODO: parse into Agent
				return file.path
			end,
		},
	})
end

-- Copy line of codes highlighted using visual mode with absolute path
function M.select_line_of_codes(opts)
	local start_line = opts.line1
	local end_line = opts.line2
	local bufname = vim.api.nvim_buf_get_name(0)
	local abs = vim.fn.fnamemodify(bufname, ':p')
	local anchor
	anchor = string.format('#L%d-L%d', start_line, end_line)

	-- TODO: parse into Agent
	local out = abs .. anchor
end

-- Receive filename(s), return absolute path(s)
function M.find_files(filenames)
	local results = {}
	for _, filename in ipairs(filenames) do
		local output = vim.fn.system(string.format('find . -name "%s"', filename))
		if output and output ~= '' then
			for _, path in ipairs(vim.split(output, '\n')) do
				if path ~= '' then
					local abs_path = vim.fn.fnamemodify(path, ':p')
					table.insert(results, abs_path)
				end
			end
		end
	end
	return results
end

function M.read_file(filepath)
	local lines = vim.fn.readfile(filepath)
	if lines then
		return table.concat(lines, '\n')
	end
end

-- Open file with temp buffer, replace contents within start_line & end_line
function M.edit_file(filepath, start_line, end_line, contents)
	local bufnr = vim.fn.bufadd(filepath)
	vim.fn.bufload(bufnr)

	if type(contents) == 'string' then
		contents = vim.split(contents, '\n')
	end

	vim.api.nvim_buf_set_lines(bufnr, start_line - 1, end_line, false, contents)

	vim.api.nvim_buf_call(bufnr, function()
		vim.cmd('write')
	end)

	return true
end

function M.write_file(filepath, contents)
	if type(contents) == 'string' then
		contents = vim.split(contents, '\n')
	end

	local result = vim.fn.writefile(contents, filepath)
	return result == 0
end

---------------------------------- External Tools -----------------------------------------------
function M.setup_external_tools()
	if vim.fn.has('mac') then
		-- bravesearch
		-- https://github.com/brave/brave-search-cli

		-- context7
		-- https://github.com/upstash/context7/blob/master/skills/context7-cli/SKILL.md
		vim.cmd(
			'terminal curl -fsSL https://raw.githubusercontent.com/brave/brave-search-cli/main/scripts/install.sh | sh && brew install ctx7'
		)
	else
		vim.cmd(
			'terminal powershell -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/brave/brave-search-cli/main/scripts/install.ps1 | iex; bun install ctx7"'
		)
	end
end

-- BraveSearch
--  web         Full web search — pages, discussions, FAQ, infobox, news, videos
--  news        News search — articles with freshness filters (pd/pw/pm/py or date range)
--  images      Image search — thumbnails, sources, dimensions
--  videos     Video search — titles, URLs, thumbnails, durations
function M.use_brave_search(type, query_content)
	local valid_types = {
		web = true,
		news = true,
		images = true,
		videos = true,
	}

	if not valid_types[type] then
		error('Invalid type: ' .. type .. '. Must be one of: web, news, images, videos')
	end

	local cmd = string.format('bx %s "%s"', type, query_content)
	local result = vim.fn.system(cmd)

	if vim.v.shell_error ~= 0 then
		error('BraveSearch failed: ' .. result)
	end

	return result
end

-- Context7
-- # Query library documentation
-- ctx7 library react "how to use hooks"
-- ctx7 docs /facebook/react "useEffect examples"
function M.use_context7(type, query_content)
	local valid_types = {
		library = true,
		docs = true,
		skills = {
			search = false,
			install = false,
			list = false,
			remove = false,
		},
	}

	if not valid_types[type] then
		error('Invalid type: ' .. type .. '. Must be one of: library, docs')
	end

	local cmd = string.format('ctx7 %s "%s"', type, query_content)
	local result = vim.fn.system(cmd)

	if vim.v.shell_error ~= 0 then
		error('Context7 failed: ' .. result)
	end

	return result
end
return M
