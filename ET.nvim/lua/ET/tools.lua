local M = {}
local fzf = require('fzf-lua')
local states = require('ET.states')

function M.select_files(callback)
	fzf.files({
		winopts = { zindex = 300 },
		actions = {
			['default'] = function(selected)
				local paths = {}
				for _, s in ipairs(selected) do
					local file = fzf.path.entry_to_file(s)
					table.insert(paths, file.path)
				end
				callback(paths)
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

local function get_virtualized_lines(filepath)
	local lines = vim.fn.readfile(filepath)

	local pending = {}
	for _, edit in ipairs(states.pending_edits) do
		if edit.filepath == filepath then
			table.insert(pending, edit)
		end
	end

	if not lines and #pending == 0 then
		return nil
	end

	if not lines then
		lines = {}
	end

	if #pending == 0 then
		return lines
	end

	table.sort(pending, function(a, b)
		return (a.start_line or 0) > (b.start_line or 0)
	end)

	for _, edit in ipairs(pending) do
		local content = edit.new_content
		if type(content) == 'string' then
			content = #content > 0 and vim.split(content, '\n') or { '' }
		end

		if edit.type == 'edit' then
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

	return lines
end

function M.read_file(filepath)
	local lines = get_virtualized_lines(filepath)
	if not lines then
		return nil
	end
	return table.concat(lines, '\n')
end

local function sanitize_content(contents)
	if type(contents) ~= 'string' then
		return contents
	end
	local first = contents:sub(1, 1)
	if (first == '"' or first == "'") and first == contents:sub(-1) then
		-- Try JSON decode first (handles all escape sequences: \n, \t, \", \\, etc.)
		local ok, decoded = pcall(vim.fn.json_decode, contents)
		if ok and type(decoded) == 'string' then
			return decoded
		end
		-- Not valid JSON: just strip the wrapping quotes
		return contents:sub(2, -2)
	end
	return contents
end

-- Search-and-replace by content (no line numbers).
-- Finds oldText in the file and replaces with newText.
-- Delegates to stage_edit for line-based staging and review.
function M.edit_file(filepath, oldText, newText)
	-- Sanitize: strip accidental string-literal wrapping from both
	newText = sanitize_content(newText)
	oldText = sanitize_content(oldText)

	local virt_content = M.read_file(filepath)
	if not virt_content then
		return { error = 'Failed to read file: ' .. filepath }
	end

	-- Find oldText in the file (plain text, exact match)
	local start_pos, end_pos = virt_content:find(oldText, 1, true)
	if not start_pos then
		-- Try to help: show what the file looks like near where we expected
		local preview = virt_content:sub(1, math.min(1000, #virt_content))
		local hint = 'oldText not found in file. Copy-paste the exact text from read_file output. File preview (first 1000 chars):\n' .. preview
		if #virt_content > 1000 then
			hint = hint .. '\n... (truncated)'
		end
		return { error = hint }
	end

	-- Calculate line numbers from position
	local before = virt_content:sub(1, start_pos - 1)
	local _, newline_count = before:gsub('\n', '')
	local start_line = newline_count + 1
	local old_lines = vim.split(oldText, '\n')
	local end_line = start_line + #old_lines - 1

	-- Delegate to line-based staging
	return M.stage_edit(filepath, start_line, end_line, newText)
end

function M.stage_edit(filepath, start_line, end_line, contents)
	contents = sanitize_content(contents)

	-- Validate: file must exist or have pending edits
	local virt_lines = get_virtualized_lines(filepath)
	if not virt_lines then
		return { error = 'Failed to read file: ' .. filepath }
	end

	-- Check for overlaps / delta shifts with prior pending edits
	for _, edit in ipairs(states.pending_edits) do
		if edit.filepath == filepath and edit.type == 'edit' then
			local nc = edit.new_content
			local n_lines = type(nc) == 'string' and #vim.split(nc, '\n') or #nc
			local delta = n_lines - (edit.end_line - edit.start_line + 1)
			if delta ~= 0 and edit.end_line < start_line then
				return { error = 'Pending edits have changed line numbers. Call read_file first.' }
			end
			local virt_end = edit.start_line + n_lines - 1
			if start_line <= virt_end and end_line >= edit.start_line then
				return { error = 'This region overlaps with a pending edit. Call read_file first.' }
			end
		end
	end

	-- Compute old_content from virtualized state
	local old_lines = {}
	for i = start_line, end_line do
		table.insert(old_lines, virt_lines[i] or '')
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

function M.apply_edits(accepted)
	for _, edit in ipairs(accepted) do
		local bufnr = vim.fn.bufadd(edit.filepath)
		vim.fn.bufload(bufnr)

		local content = edit.new_content
		if type(content) == 'string' then
			content = #content > 0 and vim.split(content, '\n') or { '' }
		end

		vim.api.nvim_buf_set_lines(bufnr, edit.start_line - 1, edit.end_line, false, content)

		vim.api.nvim_buf_call(bufnr, function()
			vim.cmd('write')
		end)
	end
end

---------------------------------- External Tools -----------------------------------------------
function M.setup_external_tools()
	local function has(cmd)
		return vim.fn.executable(cmd) == 1
	end

	local cmds = {}

	-- bx (Brave Search CLI)
	if not has('bx') then
		if vim.fn.has('mac') or not vim.fn.has('win32') then
			table.insert(cmds, 'curl -fsSL https://raw.githubusercontent.com/brave/brave-search-cli/main/scripts/install.sh | sh')
		else
			table.insert(cmds, 'powershell -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/brave/brave-search-cli/main/scripts/install.ps1 | iex"')
		end
	end

	-- ctx7
	if not has('ctx7') then
		if vim.fn.has('mac') then
			table.insert(cmds, 'brew install ctx7')
		elseif vim.fn.has('win32') then
			table.insert(cmds, 'npm install -g ctx7')
		else
			table.insert(cmds, 'npm install -g ctx7')
		end
	end

	-- jq
	if not has('jq') then
		if vim.fn.has('mac') then
			table.insert(cmds, 'brew install jq')
		elseif vim.fn.has('win32') then
			-- winget is built into Windows 10+ (no extra package manager needed)
			table.insert(cmds, 'winget install jqlang.jq --accept-package-agreements --accept-source-agreements')
		else
			table.insert(cmds, 'sudo apt-get install -y jq')
		end
	end

	-- lynx (optional on Windows — web_fetch has a Lua fallback)
	if not has('lynx') then
		if vim.fn.has('mac') then
			table.insert(cmds, 'brew install lynx')
		elseif vim.fn.has('win32') then
			-- lynx is not easily available on Windows; the Lua fallback handles it.
			-- User can install manually from https://lynx.invisible-island.net/
			vim.notify('ET.nvim: lynx not available on Windows — web_fetch will use Lua fallback', vim.log.levels.WARN)
		else
			table.insert(cmds, 'sudo apt-get install -y lynx')
		end
	end

	if #cmds == 0 then
		vim.notify('ET.nvim: All external tools are already installed', vim.log.levels.INFO)
		return
	end

	local install_cmd = table.concat(cmds, ' && ')
	vim.notify('ET.nvim: Installing ' .. #cmds .. ' missing tool(s)...', vim.log.levels.INFO)
	vim.cmd('terminal ' .. install_cmd)
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

-- WebFetch
-- Fetches and caches a web page. With a query, greps the cached content.
-- Primary HTML→text via lynx, with Lua fallback stripping.

-- Sanitize to valid UTF-8 using system iconv. Discards invalid bytes.
local function sanitize_utf8(str)
	return vim.iconv(str, 'UTF-8', 'UTF-8//IGNORE') or str
end

local function html_to_lines(raw_html)
	-- Try lynx first
	if vim.fn.executable('lynx') == 1 then
		local tmpfile = vim.fn.tempname()
		vim.fn.writefile(vim.split(raw_html, '\n'), tmpfile)
		local out = vim.fn.system(string.format('lynx -dump -stdin -nolist -width=120 < %s', vim.fn.shellescape(tmpfile)))
		vim.fn.delete(tmpfile)
		if vim.v.shell_error == 0 and out ~= '' then
			out = sanitize_utf8(out)
			return vim.split(out, '\n')
		end
	end

	-- Fallback: basic Lua stripping
	local text = sanitize_utf8(raw_html)
		:gsub('<script[^>]*>.-</script>', ' ')
		:gsub('<style[^>]*>.-</style>', ' ')
		:gsub('<[^>]+>', ' ')
		:gsub('&nbsp;', ' ')
		:gsub('&amp;', '&')
		:gsub('&lt;', '<')
		:gsub('&gt;', '>')
		:gsub('&quot;', '"')
		:gsub('&#39;', "'")
		:gsub('&[%w#]+;', ' ')

	local raw_lines = {}
	for _, line in ipairs(vim.split(text, '\n')) do
		line = line:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
		table.insert(raw_lines, line)
	end

	-- Collapse consecutive blank lines
	local lines = {}
	local prev_blank = false
	for _, line in ipairs(raw_lines) do
		if line == '' then
			if not prev_blank then
				table.insert(lines, line)
			end
			prev_blank = true
		else
			table.insert(lines, line)
			prev_blank = false
		end
	end

	return lines, nil
end

function M.web_fetch(url, query)
	if not url or url == '' then
		return { error = 'URL is required' }
	end

	-- Check cache: reuse if same URL was already fetched
	local page
	for _, p in ipairs(states.web_fetch_history) do
		if p.url == url then
			page = p
			break
		end
	end

	-- Not in cache → fetch
	if not page then
		local curl_cmd = string.format(
			'curl -sL --max-time 10 --max-filesize 1048576 %s',
			vim.fn.shellescape(url)
		)
		local raw = vim.fn.system(curl_cmd)
		raw = sanitize_utf8(raw)
		if vim.v.shell_error ~= 0 then
			return { error = 'Failed to fetch URL: ' .. (raw:gsub('^%s*(.-)%s*$', '%1') or 'unknown error') }
		end

		-- Extract title before HTML stripping
		local title = raw:match('<title[^>]*>([^<]*)</title>')

		local lines = html_to_lines(raw)
		local total = #lines

		local max_cache = 20000
		local truncated = total > max_cache
		local cached = {}
		for i = 1, math.min(total, max_cache) do
			table.insert(cached, lines[i])
		end

		-- Fallback title from first non-blank line
		if not title or title == '' then
			for i = 1, math.min(10, #cached) do
				if cached[i] ~= '' then
					title = cached[i]
					break
				end
			end
		end

		page = {
			url = url,
			title = title or '',
			lines = cached,
			total_lines = total,
			truncated = truncated,
		}
		table.insert(states.web_fetch_history, page)
	end

	-- Query mode: grep cached content
	if query and query ~= '' and page.lines and #page.lines > 0 then
		local pattern = query:lower()
		local matches = {}
		local context = 2

		for i, line in ipairs(page.lines) do
			if line:lower():find(pattern, 1, true) then
				local start = math.max(1, i - context)
				local finish = math.min(#page.lines, i + context)
				local block_lines = {}
				for j = start, finish do
					local marker = j == i and '>' or ' '
					table.insert(block_lines, string.format('%s %d: %s', marker, j, page.lines[j]))
				end
				table.insert(matches, block_lines)
				if #matches >= 25 then
					break
				end
			end
		end

		if #matches == 0 then
			return {
				url = url,
				query = query,
				matches = 0,
				message = string.format('No matches for "%s" in cached page (%d lines).', query, page.total_lines),
			}
		end

		local first_line = tonumber(matches[1][1]:match('^> (%d+):')) or 0
		local last_line = tonumber(matches[#matches][1]:match('^> (%d+):')) or 0

		local summary = string.format(
			'%d match%s across lines %d-%d (%d lines cached%s)',
			#matches,
			#matches == 1 and '' or 'es',
			first_line,
			last_line,
			page.total_lines,
			page.truncated and ', truncated' or ''
		)

		return {
			url = url,
			title = page.title,
			query = query,
			matches = #matches,
			summary = summary,
			results = matches,
		}
	end

	-- Preview mode: return first 200 lines
	local preview_lines = {}
	local preview_count = math.min(200, #page.lines)
	for i = 1, preview_count do
		table.insert(preview_lines, page.lines[i])
	end

	local result = {
		url = url,
		title = page.title,
		total_lines = page.total_lines,
		cached_lines = #page.lines,
		truncated = page.truncated,
		preview = table.concat(preview_lines, '\n'),
		hint = 'Use web_fetch(url, "query") to search this page.',
	}

	if page.truncated then
		result.warning = string.format(
			'Content past line %d is not cached. Use a more specific URL to narrow.',
			#page.lines
		)
	end

	return result
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
			description = 'Make a precise edit. oldText must match exactly (copy-paste from read_file output). newText is the replacement. The tool finds oldText in the file and replaces it.',
			parameters = {
				type = 'object',
				properties = {
					filepath = { type = 'string' },
					oldText = { type = 'string', description = 'Exact text to replace. Must match the file character-for-character including whitespace. Copy-paste from read_file.' },
					newText = { type = 'string', description = 'Replacement text. Only the text you want to change — do not include surrounding unchanged lines.' },
				},
				required = { 'filepath', 'oldText', 'newText' },
			},
		},
	},
	{
		type = 'function',
		['function'] = {
			name = 'web_fetch',
			description = 'Fetch a web page and cache it. Use without query to get a preview. Use with query to grep the cached page for matching lines (case-insensitive).',
			parameters = {
				type = 'object',
				properties = {
					url = { type = 'string', description = 'Full URL including https://' },
					query = { type = 'string', description = 'Optional: text to search for within the page' },
				},
				required = { 'url' },
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
		return M.edit_file(args.filepath, args.oldText, args.newText)
	elseif name == 'web_fetch' then
		return M.web_fetch(args.url, args.query)
	elseif name == 'done' then
		return { stop = true, message = args.message or 'Task completed' }
	end
	return { error = 'Unknown tool: ' .. tostring(name) }
end

return M
