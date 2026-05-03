local M = {}
local fzf = require('fzf-lua')

function M.select_files(callback)
	fzf.files({
		actions = {
			['default'] = function(selected)
				local paths = {}
				for _, s in ipairs(selected) do
					local file = fzf.path.entry_to_file(s)
					table.insert(paths, file.path)
				end
				if callback then
					callback(paths)
				end
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
	return out
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
		-- Install bx (brave-search-cli), ctx7, jq
		vim.cmd(
			'terminal curl -fsSL https://raw.githubusercontent.com/brave/brave-search-cli/main/scripts/install.sh | sh && brew install ctx7 jq'
		)
	else
		-- Install bx, ctx7, jq (using chocolatey for jq)
		vim.cmd(
			'terminal powershell -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/brave/brave-search-cli/main/scripts/install.ps1 | iex; choco install jq -y; bun install ctx7"'
		)
	end
end

-- BraveSearch
--  web         Full web search — pages, discussions, FAQ, infobox, news, videos
--  news        News search — articles with freshness filters (pd/pw/pm/py or date range)
--  images      Image search — thumbnails, sources, dimensions
--  videos     Video search — titles, URLs, thumbnails, durations
function M.use_brave_search(search_type, query_content, count)
	local valid_types = {
		web = true,
		news = true,
		images = true,
		videos = true,
	}

	if not valid_types[search_type] then
		error('Invalid search type: ' .. search_type .. '. Must be one of: web, news, images, videos')
	end

	-- Check dependencies
	if vim.fn.executable('bx') == 0 then
		error('bx (Brave Search CLI) is not installed. Run :ETInstallTools')
	end
	if vim.fn.executable('jq') == 0 then
		error('jq is not installed. Run :ETInstallTools')
	end

	count = count or 5
	local query_escaped = vim.fn.shellescape(query_content)
	local cmd_parts = { 'bx', search_type, query_escaped, '--count', tostring(count) }

	-- Type-specific flags and jq filters
	local jq_filter
	if search_type == 'web' then
		-- Only return web results, exclude news/videos/discussions
		table.insert(cmd_parts, '--result-filter')
		table.insert(cmd_parts, 'web')
		jq_filter = '[.web.results[] | {title, url, description}]'
	elseif search_type == 'news' then
		jq_filter = '[.results[] | {title, url, age, description}]'
	elseif search_type == 'images' then
		jq_filter = '[.results[] | {title, url, source, thumbnail: .thumbnail.src}]'
	elseif search_type == 'videos' then
		jq_filter = '[.results[] | {title, url, duration: .video.duration, thumbnail: .thumbnail}]'
	end

	local cmd = table.concat(cmd_parts, ' ') .. ' | jq -c ' .. vim.fn.shellescape(jq_filter)
	local result = vim.fn.system(cmd)

	if vim.v.shell_error ~= 0 then
		error('BraveSearch failed: ' .. result)
	end

	-- Parse jq output (single line JSON array)
	result = result:gsub('^%s*(.-)%s*$', '%1') -- trim whitespace
	if result == '' then
		return {}
	end

	local ok, decoded = pcall(vim.fn.json_decode, result)
	if not ok or type(decoded) ~= 'table' then
		error('Failed to parse BraveSearch results: ' .. result)
	end

	return decoded
end

-- Context7
-- # Query library documentation
-- ctx7 library --json "react"
-- ctx7 docs --json /facebook/react "useEffect examples"
function M.use_context7(ctx7_type, query_content, library_id)
	local valid_types = {
		library = true,
		docs = true,
	}

	if not valid_types[ctx7_type] then
		error('Invalid type: ' .. ctx7_type .. '. Must be one of: library, docs')
	end

	if vim.fn.executable('ctx7') == 0 then
		error('ctx7 is not installed. Run :ETInstallTools')
	end

	local cmd
	if ctx7_type == 'docs' then
		if not library_id or library_id == '' then
			error('library_id is required for docs type')
		end
		local lib_escaped = vim.fn.shellescape(library_id)
		local query_escaped = vim.fn.shellescape(query_content)
		cmd = string.format('ctx7 docs --json %s %s', lib_escaped, query_escaped)
	else
		local query_escaped = vim.fn.shellescape(query_content)
		cmd = string.format('ctx7 library --json %s', query_escaped)
	end
	local result = vim.fn.system(cmd)

	if vim.v.shell_error ~= 0 then
		error('Context7 failed: ' .. result)
	end

	result = result:gsub('^%s*(.-)%s*$', '%1')
	if result == '' then
		return {}
	end

	local ok, decoded = pcall(vim.fn.json_decode, result)
	if not ok or type(decoded) ~= 'table' then
		error('Failed to parse Context7 results: ' .. result)
	end

	return decoded
end
return M
