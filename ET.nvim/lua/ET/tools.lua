local M = {}
local fzf = require('fzf-lua')
local states = require('ET.states')

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
function M.select_line_of_codes(opts, bufnr)
	local start_line = opts.line1
	local end_line = opts.line2
	local buf = bufnr or vim.api.nvim_get_current_buf()
	local bufname = vim.api.nvim_buf_get_name(buf)
	local abs = vim.fn.fnamemodify(bufname, ':p')
	local anchor = string.format('#L%d-L%d', start_line, end_line)

	local content_lines = vim.api.nvim_buf_get_lines(buf, start_line - 1, end_line, false)
	local content = table.concat(content_lines, '\n')

	local out = abs .. anchor .. '\n```\n' .. content .. '\n```'
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
	if not lines then
		return nil
	end

	local pending = {}
	for _, edit in ipairs(states.pending_edits) do
		if edit.filepath == filepath then
			table.insert(pending, edit)
		end
	end

	if #pending > 0 then
		table.sort(pending, function(a, b)
			return (a.start_line or 0) > (b.start_line or 0)
		end)

		for _, edit in ipairs(pending) do
			local content = edit.new_content
			if type(content) == 'string' then
				content = #content > 0 and vim.split(content, '\n') or { '' }
			end

			if edit.type == 'write' then
				lines = content
			elseif edit.type == 'edit' then
				local result = {}
				for i = 1, edit.start_line - 1 do
					table.insert(result, lines[i] or '')
				end
				for _, l in ipairs(content) do
					table.insert(result, l)
				end
				for i = edit.end_line + 1, #lines do
					table.insert(result, lines[i])
				end
				lines = result
			end
		end
	end

	return table.concat(lines, '\n')
end

function M.stage_edit(filepath, start_line, end_line, contents)
	local lines = vim.fn.readfile(filepath)
	if not lines then
		return { error = 'Failed to read file: ' .. filepath }
	end

	local old_lines = {}
	for i = start_line, end_line do
		table.insert(old_lines, lines[i] or '')
	end
	local old_content = table.concat(old_lines, '\n')

	table.insert(states.pending_edits, {
		type = 'edit',
		filepath = filepath,
		start_line = start_line,
		end_line = end_line,
		old_content = old_content,
		new_content = contents,
	})

	return { staged = true }
end

function M.stage_write(filepath, contents)
	local old_content = ''
	local lines = vim.fn.readfile(filepath)
	if lines then
		old_content = table.concat(lines, '\n')
	end

	table.insert(states.pending_edits, {
		type = 'write',
		filepath = filepath,
		old_content = old_content,
		new_content = contents,
	})

	return { staged = true }
end

function M.apply_edits(accepted)
	for _, edit in ipairs(accepted) do
		local bufnr = vim.fn.bufadd(edit.filepath)
		vim.fn.bufload(bufnr)

		local content = edit.new_content
		if type(content) == 'string' then
			content = #content > 0 and vim.split(content, '\n') or { '' }
		end

		if edit.type == 'edit' then
			vim.api.nvim_buf_set_lines(bufnr, edit.start_line - 1, edit.end_line, false, content)
		elseif edit.type == 'write' then
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)
		end

		vim.api.nvim_buf_call(bufnr, function()
			vim.cmd('write')
		end)
	end
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

M.tool_definitions = {
	{
		type = 'function',
		['function'] = {
			name = 'find_files',
			description = 'Find files by name pattern in the project directory',
			parameters = {
				type = 'object',
				properties = {
					filenames = {
						type = 'array',
						items = { type = 'string' },
						description = 'List of filenames or glob patterns to search for',
					},
				},
				required = { 'filenames' },
			},
		},
	},
	{
		type = 'function',
		['function'] = {
			name = 'read_file',
			description = 'Read the contents of a file',
			parameters = {
				type = 'object',
				properties = {
					filepath = {
						type = 'string',
						description = 'Absolute path to the file',
					},
				},
				required = { 'filepath' },
			},
		},
	},
	{
		type = 'function',
		['function'] = {
			name = 'edit_file',
			description = 'Replace lines in a file between start_line and end_line with new contents',
			parameters = {
				type = 'object',
				properties = {
					filepath = { type = 'string' },
					start_line = { type = 'integer' },
					end_line = { type = 'integer' },
					contents = { type = 'string', description = 'New content to replace the lines with' },
				},
				required = { 'filepath', 'start_line', 'end_line', 'contents' },
			},
		},
	},
	{
		type = 'function',
		['function'] = {
			name = 'write_file',
			description = 'Write contents to a file (creates or overwrites)',
			parameters = {
				type = 'object',
				properties = {
					filepath = { type = 'string' },
					contents = { type = 'string', description = 'Content to write to the file' },
				},
				required = { 'filepath', 'contents' },
			},
		},
	},
	{
		type = 'function',
		['function'] = {
			name = 'done',
			description = 'Call when the task is complete. Summarize what was accomplished.',
			parameters = {
				type = 'object',
				properties = {
					message = { type = 'string', description = 'Summary of what was done' },
				},
				required = { 'message' },
			},
		},
	},
}

function M.dispatch(name, args)
	if name == 'find_files' then
		return M.find_files(args.filenames)
	elseif name == 'read_file' then
		return M.read_file(args.filepath)
	elseif name == 'edit_file' then
		return M.stage_edit(args.filepath, args.start_line, args.end_line, args.contents)
	elseif name == 'write_file' then
		return M.stage_write(args.filepath, args.contents)
	elseif name == 'done' then
		return { stop = true, message = args.message or 'Task completed' }
	end
	return { error = 'Unknown tool: ' .. tostring(name) }
end

return M
