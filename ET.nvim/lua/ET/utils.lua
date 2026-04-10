local M = {}

local popup = require('plenary.popup')

local function strip_ansi_codes(text)
	return (text or ''):gsub('\27%[[%d;]*m', '')
end

local function is_probably_path(path)
	if not path or path == '' then
		return false
	end
	return vim.fn.filereadable(path) == 1 or vim.fn.isdirectory(path) == 1
end

function M.normalize_fzf_file_entry(entry)
	local clean = vim.trim(strip_ansi_codes(entry or ''))
	local starts_like_path = clean:match('[%./~%w].*$')
	if starts_like_path and starts_like_path ~= '' then
		clean = vim.trim(starts_like_path)
	end

	if is_probably_path(clean) then
		return clean
	end

	local tail = clean:match('([^%s]+)$')
	if is_probably_path(tail) then
		return tail
	end

	local no_icon = vim.trim(clean:gsub('^[^%./~%w]+', ''))
	no_icon = vim.trim(no_icon:gsub('^%S+%s+', ''))
	if is_probably_path(no_icon) then
		return no_icon
	end

	return no_icon ~= '' and no_icon or clean
end

local function focus_fzf_window()
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local buf = vim.api.nvim_win_get_buf(win)
		if vim.bo[buf].filetype == 'fzf' then
			pcall(vim.api.nvim_set_current_win, win)
			pcall(vim.cmd, 'startinsert')
			return true
		end
	end
	return false
end

local function schedule_focus_fzf_retries()
	local delays = { 10, 40, 120 }
	for _, delay in ipairs(delays) do
		vim.defer_fn(function()
			focus_fzf_window()
		end, delay)
	end
end

local function extract_message_content(content)
	if type(content) == 'string' then
		return content
	end

	if type(content) == 'table' then
		local parts = {}
		for _, block in ipairs(content) do
			if type(block) == 'string' then
				table.insert(parts, block)
			elseif type(block) == 'table' then
				if type(block.text) == 'string' then
					table.insert(parts, block.text)
				elseif type(block.content) == 'string' then
					table.insert(parts, block.content)
				end
			end
		end
		return table.concat(parts, '')
	end

	return ''
end

local function parse_stream_text(raw)
	local chunks = {}
	for line in raw:gmatch('[^\r\n]+') do
		local data = line:match('^data:%s*(.*)$') or line
		if data ~= '' and data ~= '[DONE]' then
			local ok, payload = pcall(vim.fn.json_decode, data)
			if ok and type(payload) == 'table' then
				local choice = payload.choices and payload.choices[1] or nil
				local delta = choice and choice.delta or nil
				local piece = nil

				if delta then
					piece = extract_message_content(delta.content)
				end

				if (piece == nil or piece == '') and choice and choice.message then
					piece = extract_message_content(choice.message.content)
				end

				if (piece == nil or piece == '') and choice and type(choice.text) == 'string' then
					piece = choice.text
				end

				if piece and piece ~= '' then
					table.insert(chunks, piece)
				end
			end
		end
	end

	return table.concat(chunks, '')
end

function M.close_win(win_id)
	if vim.api.nvim_win_is_valid(win_id) then
		vim.api.nvim_win_close(win_id, true)
	end
end

function M.parse_response(resp)
	if type(resp) == 'string' then
		local parsed_stream = parse_stream_text(resp)
		if parsed_stream ~= '' then
			return parsed_stream
		end
		return resp
	end

	if resp and resp.choices and resp.choices[1] then
		local choice = resp.choices[1]
		if choice.message then
			local content = extract_message_content(choice.message.content)
			if content ~= '' then
				return content
			end
		end

		if choice.delta then
			local delta_content = extract_message_content(choice.delta.content)
			if delta_content ~= '' then
				return delta_content
			end
		end

		if type(choice.text) == 'string' and choice.text ~= '' then
			return choice.text
		end
	end

	if resp and resp.message and type(resp.message) == 'string' then
		return resp.message
	end

	if type(resp) == 'table' then
		return vim.fn.json_encode(resp)
	end

	return tostring(resp or '')
end

function M.set_popup_lines(bufnr, lines)
	vim.api.nvim_set_option_value('modifiable', true, { buf = bufnr })
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	vim.api.nvim_set_option_value('modifiable', false, { buf = bufnr })
end

function M.normalize_model_label(value)
	local model = vim.trim(value or '')
	if vim.startswith(model, '● ') or vim.startswith(model, '○ ') then
		model = model:sub(5)
	end
	return vim.trim(model)
end

function M.notify_error(message)
	vim.notify(message, vim.log.levels.ERROR)
end

function M.create_centered_popup(lines, opts)
	opts = opts or {}
	local width_ratio = opts.width_ratio or 0.78
	local height_ratio = opts.height_ratio or 0.55
	local minwidth = opts.minwidth or 60
	local minheight = opts.minheight or 6
	local maxwidth = opts.maxwidth or math.floor(vim.o.columns * 0.95)
	local maxheight = opts.maxheight or math.floor(vim.o.lines * 0.9)

	local computed_width = math.floor(vim.o.columns * width_ratio)
	local computed_height = math.floor(vim.o.lines * height_ratio)
	local width = math.max(minwidth, math.min(maxwidth, computed_width))
	local height = opts.height or math.max(minheight, math.min(maxheight, computed_height))

	local popup_opts = {
		title = opts.title,
		minwidth = width,
		line = math.floor(((vim.o.lines - height) / 2) - 1),
		col = math.floor((vim.o.columns - width) / 2),
		border = opts.border or {},
		enter = opts.enter ~= false,
		cursorline = opts.cursorline,
		callback = opts.callback,
		finalize_callback = opts.finalize_callback,
	}

	return popup.create(lines, popup_opts)
end

function M.title_for_mode(mode)
	if mode == 'agent' then
		return 'ET Agent'
	end

	return 'ET Chat'
end

function M.resolve_mode_from_title(title)
	if title == 'ET Agent' then
		return 'agent'
	end

	return 'chat'
end

function M.append_text_to_popup(bufnr, text)
	local existing = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	if #existing == 0 then
		existing = { '' }
	end

	local merged = table.concat(existing, '\n') .. (text or '')
	local lines = vim.split(merged, '\n', { plain = true })
	M.set_popup_lines(bufnr, lines)
end

function M.try_open_fzf_file_picker(on_select, opts)
	opts = opts or {}
	local ok, fzf = pcall(require, 'fzf-lua')
	if not ok then
		M.notify_error('fzf-lua is required for @ file picker')
		return false
	end

	local on_done = opts.on_done

	fzf.files({
		fzf_opts = vim.tbl_deep_extend('force', {
			['--multi'] = true,
		}, opts.fzf_opts or {}),
		winopts = vim.tbl_deep_extend('force', {
			zindex = 220,
			on_create = function()
				focus_fzf_window()
			end,
			on_close = function()
				if on_done then
					on_done()
				end
				if opts.on_close then
					opts.on_close()
				end
			end,
		}, opts.winopts or {}),
		actions = {
			['default'] = function(selected)
				if not selected or #selected == 0 then
					return
				end
				local normalized = {}
				for _, entry in ipairs(selected) do
					table.insert(normalized, M.normalize_fzf_file_entry(entry))
				end
				on_select(normalized)
			end,
		},
	})
	schedule_focus_fzf_retries()

	return true
end

function M.try_open_fzf_lines(path, on_select_line, opts)
	opts = opts or {}
	local ok, fzf = pcall(require, 'fzf-lua')
	if not ok then
		M.notify_error('fzf-lua is required for line picker')
		return false
	end

	fzf.blines({
		fname = path,
		winopts = vim.tbl_deep_extend('force', {
			zindex = 220,
			on_create = function()
				focus_fzf_window()
			end,
			on_close = opts.on_close,
		}, opts.winopts or {}),
		actions = {
			['default'] = function(selected)
				if not selected or not selected[1] then
					return
				end
				on_select_line(selected[1])
			end,
		},
	})
	schedule_focus_fzf_retries()

	return true
end

return M
