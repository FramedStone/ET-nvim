local M = {}

local provider = require('ET.provider.omlx')
local config = require('ET.config')
local utils = require('ET.utils')
local state = require('ET.state')
local popup = require('plenary.popup')

local function extract_prompt_from_lines(lines)
	if not lines or #lines == 0 then
		return ''
	end

	local marker_idx = nil
	for i = #lines, 1, -1 do
		if lines[i]:match('^>%s?') then
			marker_idx = i
			break
		end
	end

	if not marker_idx then
		return vim.trim(table.concat(lines, '\n'))
	end

	local prompt_lines = {}
	for i = marker_idx, #lines do
		prompt_lines[#prompt_lines + 1] = lines[i]
	end

	prompt_lines[1] = prompt_lines[1]:gsub('^>%s?', '')
	return vim.trim(table.concat(prompt_lines, '\n'))
end

local function resize_chat_popup(win_id, line_count)
	if not vim.api.nvim_win_is_valid(win_id) then
		return
	end

	local width = math.max(90, math.floor(vim.o.columns * 0.9))
	local max_height = math.floor(vim.o.lines * 0.9)
	local height = math.min(max_height, math.max(10, line_count + 4))
	local row = math.floor(((vim.o.lines - height) / 2) - 1)
	local col = math.floor((vim.o.columns - width) / 2)

	pcall(popup.move, win_id, {
		line = row,
		col = col,
		width = width,
		height = height,
	})
end

local function reset_chat_popup_size(win_id)
	if not vim.api.nvim_win_is_valid(win_id) then
		return
	end

	local width = math.max(90, math.floor(vim.o.columns * 0.82))
	local height = math.max(10, math.floor(vim.o.lines * 0.55))
	local row = math.floor(((vim.o.lines - height) / 2) - 1)
	local col = math.floor((vim.o.columns - width) / 2)

	pcall(popup.move, win_id, {
		line = row,
		col = col,
		width = width,
		height = height,
	})
end

local function scroll_chat_to_bottom(win_id, bufnr)
	if not vim.api.nvim_win_is_valid(win_id) or not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end
	local line_count = vim.api.nvim_buf_line_count(bufnr)
	pcall(vim.api.nvim_win_set_cursor, win_id, { line_count, 0 })
end

local function stream_text_to_popup(text, on_update, on_done)
	local chars = vim.split(text or '', '', { plain = true, trimempty = false })
	if #chars == 0 then
		on_done('')
		return
	end

	local timer = vim.uv.new_timer()
	local idx = 1
	local acc = ''
	local function finish()
		if timer then
			timer:stop()
			timer:close()
			timer = nil
		end
		on_done(acc)
	end

	timer:start(0, 8, function()
		vim.schedule(function()
			local step = 8
			for _ = 1, step do
				if idx > #chars then
					break
				end
				acc = acc .. chars[idx]
				idx = idx + 1
			end

			on_update(acc)

			if idx > #chars then
				finish()
			end
		end)
	end)
end

local function split_history_and_prompt(lines)
	local marker_idx = nil
	for i = #lines, 1, -1 do
		if lines[i]:match('^>%s?') then
			marker_idx = i
			break
		end
	end

	if not marker_idx then
		return lines, ''
	end

	local history_lines = {}
	for i = 1, marker_idx - 1 do
		history_lines[#history_lines + 1] = lines[i]
	end

	local prompt_lines = {}
	for i = marker_idx, #lines do
		prompt_lines[#prompt_lines + 1] = lines[i]
	end
	prompt_lines[1] = prompt_lines[1]:gsub('^>%s?', '')

	return history_lines, vim.trim(table.concat(prompt_lines, '\n'))
end

local function parse_history_messages(history_lines)
	local messages = {}
	local current_role = nil
	local current_lines = {}

	local function flush_current()
		if not current_role then
			return
		end
		local content = vim.trim(table.concat(current_lines, '\n'))
		if content ~= '' then
			table.insert(messages, { role = current_role, content = content })
		end
		current_lines = {}
	end

	for _, line in ipairs(history_lines or {}) do
		if line == 'You:' then
			flush_current()
			current_role = 'user'
		elseif line == 'Assistant:' then
			flush_current()
			current_role = 'assistant'
		else
			if current_role then
				table.insert(current_lines, line)
			end
		end
	end

	flush_current()
	return messages
end

local function open_range_selector(path, on_done)
	local resolved_path = vim.fn.fnamemodify(path, ':p')
	if vim.fn.filereadable(resolved_path) ~= 1 then
		utils.notify_error('Cannot open file for range selection: ' .. tostring(path))
		on_done(nil, false, resolved_path)
		return
	end

	local ok, file_lines = pcall(vim.fn.readfile, resolved_path)
	if not ok then
		utils.notify_error('Failed reading file for range selection: ' .. tostring(resolved_path))
		on_done(nil, false, resolved_path)
		return
	end

	if not file_lines or #file_lines == 0 then
		utils.notify_error('File is empty, cannot pick range: ' .. tostring(resolved_path))
		on_done(nil, false, resolved_path)
		return
	end

	local display_lines = {}
	for i, text in ipairs(file_lines) do
		display_lines[i] = string.format('%4d | %s', i, text)
	end

	utils.create_centered_popup(display_lines, {
		title = 'Select code range (visual mode + <CR>, q = whole file)',
		minwidth = 110,
		minheight = 10,
		height = math.min(#display_lines + 2, math.floor(vim.o.lines * 0.75)),
		width_ratio = 0.9,
		border = {},
		enter = true,
		cursorline = true,
		finalize_callback = function(range_win, range_buf)
			vim.schedule(function()
				if vim.api.nvim_win_is_valid(range_win) then
					pcall(vim.api.nvim_set_current_win, range_win)
					pcall(vim.cmd, 'stopinsert')
				end
			end)

			local function finish(selection)
				if vim.api.nvim_win_is_valid(range_win) then
					vim.api.nvim_win_close(range_win, true)
				end
				on_done(selection, false, resolved_path)
			end

			local function confirm_visual_selection()
				local cur_line = vim.api.nvim_win_get_cursor(range_win)[1]
				local visual_line = vim.fn.line('v')
				if visual_line <= 0 then
					vim.notify('Use visual mode to select lines, then press <CR>.', vim.log.levels.INFO)
					return
				end

				local start_line = math.min(cur_line, visual_line)
				local end_line = math.max(cur_line, visual_line)
				finish({ start_line = start_line, end_line = end_line })
			end

			local function cancel_to_whole_file()
				if vim.api.nvim_win_is_valid(range_win) then
					vim.api.nvim_win_close(range_win, true)
				end
				on_done(nil, true, resolved_path)
			end

			vim.keymap.set('x', '<CR>', confirm_visual_selection, { buffer = range_buf, silent = true })
			vim.keymap.set('n', '<CR>', function()
				vim.notify('Enter visual mode and select lines first, then press <CR>.', vim.log.levels.INFO)
			end, { buffer = range_buf, silent = true })
			vim.keymap.set('n', 'q', cancel_to_whole_file, { buffer = range_buf, silent = true })
			vim.keymap.set('n', '<Esc>', cancel_to_whole_file, { buffer = range_buf, silent = true })
			vim.keymap.set('x', '<Esc>', cancel_to_whole_file, { buffer = range_buf, silent = true })
		end,
	})
end

local function append_mentions_to_active_chat(mentions)
	if not mentions or #mentions == 0 then
		return false
	end

	local win_id, bufnr = state.get_active_chat_window()
	if not win_id or not bufnr then
		utils.notify_error('No active ET chat window. Start ETChat/ETAgent/ETExplain first.')
		return false
	end

	if not vim.api.nvim_win_is_valid(win_id) or not vim.api.nvim_buf_is_valid(bufnr) then
		utils.notify_error('Active ET chat window is no longer valid.')
		return false
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	while #lines > 0 and vim.trim(lines[#lines]) == '' do
		table.remove(lines)
	end

	local text = table.concat(lines, '\n')
	local updated
	if text:match('@%s*$') then
		updated = text:gsub('@%s*$', mentions[1], 1)
		for i = 2, #mentions do
			updated = updated .. '\n' .. mentions[i]
		end
	elseif text == '' then
		updated = table.concat(mentions, '\n')
	else
		updated = text .. '\n' .. table.concat(mentions, '\n')
	end

	local updated_lines = vim.split(updated, '\n', { plain = true })
	if updated_lines[#updated_lines] ~= '' then
		table.insert(updated_lines, '')
	end

	utils.set_popup_lines(bufnr, updated_lines)
	vim.api.nvim_set_option_value('buftype', 'acwrite', { buf = bufnr })
	vim.api.nvim_set_option_value('modifiable', true, { buf = bufnr })
	vim.bo[bufnr].modified = true
	state.set_ui_status('input')
	pcall(vim.api.nvim_set_current_win, win_id)
	pcall(vim.api.nvim_win_set_cursor, win_id, { #updated_lines, 0 })
	pcall(vim.cmd, 'stopinsert')
	return true
end

function M.file_picker()
	local references = {}

	local function process_selected_file(index, paths, done)
		local path = paths[index]
		if not path then
			done()
			return
		end

		open_range_selector(path, function(selection, cancelled, resolved_path)
			if not selection and not cancelled then
				done()
				return
			end

			if selection and selection.start_line and selection.end_line then
				table.insert(references, string.format('@%s#L%d-L%d', resolved_path, selection.start_line, selection.end_line))
			else
				table.insert(references, string.format('@%s', resolved_path))
			end

			process_selected_file(index + 1, paths, done)
		end)
	end

	local opened = utils.try_open_fzf_file_picker(function(paths)
		if not paths or #paths == 0 then
			return
		end

		local resolved_paths = {}
		for _, p in ipairs(paths) do
			local abs = vim.fn.fnamemodify(p, ':p')
			if vim.fn.filereadable(abs) == 1 then
				table.insert(resolved_paths, abs)
			end
		end

		if #resolved_paths == 0 then
			utils.notify_error('No readable files selected from picker')
			return
		end

		process_selected_file(1, resolved_paths, function()
			append_mentions_to_active_chat(references)
		end)
	end)

	if not opened then
		utils.notify_error('Failed to open ET file picker')
	end
end

function M.switch_model()
	local ok, models = pcall(provider.list_models)
	if not ok then
		utils.notify_error('ETSwitchModel error: ' .. tostring(models))
		return
	end

	if not models or #models == 0 then
		utils.notify_error('ETSwitchModel error: No models returned by oMLX endpoint')
		return
	end

	local current_model = utils.normalize_model_label(config.get_config().omlx.model or '')
	local display_models = {}
	local current_index = nil
	for i, model in ipairs(models) do
		if model == current_model then
			display_models[i] = '● ' .. model
			current_index = i
		else
			display_models[i] = '○ ' .. model
		end
	end

	utils.create_centered_popup(display_models, {
		title = 'ET Switch Model',
		minwidth = 60,
		height = #models + 2,
		border = {},
		enter = true,
		cursorline = true,
		callback = function(_, selected)
			if selected and selected ~= '' then
				local model = utils.normalize_model_label(selected)
				config.set_config({ omlx = { model = model } })
				vim.notify('ET model switched to: ' .. model)
			end
		end,
		finalize_callback = function(win_id, bufnr)
			if current_index then
				pcall(vim.api.nvim_win_set_cursor, win_id, { current_index, 0 })
			end
			vim.keymap.set('n', 'q', function()
				utils.close_win(win_id)
			end, { buffer = bufnr, silent = true })
		end,
	})
end

function M.chat()
	M.start_mode('chat')
end

function M.start_mode(mode)
	state.reset_state()
	state.set_mode(mode)
	state.set_ui_status('input')

	local title = utils.title_for_mode(mode)

	utils.create_centered_popup({ '', '', '', '', '', '', '', '' }, {
		title = title,
		minwidth = 90,
		minheight = 10,
		height_ratio = 0.55,
		width_ratio = 0.82,
		border = {},
		enter = true,
		finalize_callback = function(win_id, bufnr)
			state.set_active_chat_window(win_id, bufnr)
			if vim.api.nvim_buf_get_name(bufnr) == '' then
				vim.api.nvim_buf_set_name(bufnr, 'et://chat-input')
			end
			local ns = vim.api.nvim_create_namespace('et_chat_processing')
			local spinner_label = 'Processing'
			local spinner_frames = {}
			local spinner_timer = nil
			local spinner_idx = 1
			local spinner_mark_id = nil
			local mode = 'input'
			vim.api.nvim_set_option_value('buftype', 'acwrite', { buf = bufnr })
			vim.api.nvim_set_option_value('bufhidden', 'wipe', { buf = bufnr })
			vim.api.nvim_set_option_value('buflisted', false, { buf = bufnr })
			vim.api.nvim_set_option_value('modifiable', true, { buf = bufnr })
			vim.bo[bufnr].modified = true
			utils.set_popup_lines(bufnr, { '> ' })
			vim.api.nvim_set_option_value('modifiable', true, { buf = bufnr })
			reset_chat_popup_size(win_id)
			scroll_chat_to_bottom(win_id, bufnr)
			pcall(vim.api.nvim_win_set_cursor, win_id, { 1, 2 })
			pcall(vim.cmd, 'stopinsert')

			local function stop_spinner()
				if spinner_timer then
					spinner_timer:stop()
					spinner_timer:close()
					spinner_timer = nil
				end
			end

			local function rebuild_spinner_frames()
				spinner_frames = {
					spinner_label .. '   ',
					spinner_label .. '.  ',
					spinner_label .. '.. ',
					spinner_label .. '...',
				}
			end

			local function set_status(label)
				if label and label ~= '' then
					state.set_ui_status(label)
					spinner_label = label
					rebuild_spinner_frames()
				end
			end

			local function start_spinner()
				stop_spinner()
				rebuild_spinner_frames()
				spinner_idx = 1
				spinner_timer = vim.uv.new_timer()
				spinner_timer:start(0, 180, function()
					vim.schedule(function()
						if not vim.api.nvim_buf_is_valid(bufnr) then
							stop_spinner()
							return
						end
						local line_count = vim.api.nvim_buf_line_count(bufnr)
						local target_row = math.max(0, line_count - 1)
						spinner_mark_id = vim.api.nvim_buf_set_extmark(bufnr, ns, target_row, 0, {
							id = spinner_mark_id,
							virt_text = { { spinner_frames[spinner_idx], 'Comment' } },
							virt_text_pos = 'eol',
						})
						spinner_idx = (spinner_idx % #spinner_frames) + 1
					end)
				end)
			end

			local function cancel()
				stop_spinner()
				state.set_ui_status('cancelled')
				utils.close_win(win_id)
			end

			vim.keymap.set('n', '<M-f>', function()
				pcall(vim.api.nvim_set_current_win, win_id)
				M.file_picker()
			end, { buffer = bufnr, silent = true })
			vim.keymap.set('i', '<M-f>', function()
				vim.cmd('stopinsert')
				pcall(vim.api.nvim_set_current_win, win_id)
				M.file_picker()
			end, { buffer = bufnr, silent = true })

			vim.api.nvim_create_autocmd('BufWriteCmd', {
				buffer = bufnr,
				callback = function()
					if mode ~= 'input' then
						return
					end
					local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
					local history_lines, input = split_history_and_prompt(lines)

					if input == '' then
						return
					end

					local user_block = vim.list_extend({ 'You:' }, vim.split(input, '\n', { plain = true }))
					local processing_lines = vim.list_extend(vim.deepcopy(history_lines), user_block)
					table.insert(processing_lines, '')
					table.insert(processing_lines, 'Assistant:')

					mode = 'response'
					set_status('Processing')
					start_spinner()
					reset_chat_popup_size(win_id)
					utils.set_popup_lines(bufnr, processing_lines)
					resize_chat_popup(win_id, #processing_lines)
					scroll_chat_to_bottom(win_id, bufnr)
					vim.api.nvim_set_option_value('buftype', 'nofile', { buf = bufnr })

					vim.keymap.set('n', 'q', cancel, { buffer = bufnr, silent = true })
					vim.keymap.set('i', 'q', cancel, { buffer = bufnr, silent = true })

					local request_messages = { { role = 'user', content = input } }
					if state.get_mode() == 'chat' then
						request_messages = parse_history_messages(history_lines)
						table.insert(request_messages, { role = 'user', content = input })

						state.update_state('temp_history', {})
						for _, msg in ipairs(request_messages) do
							state.add_to_temp_history(msg.role, msg.content)
						end
					end

					provider.chat_async(request_messages, function(ok, resp_or_err)
						if not vim.api.nvim_buf_is_valid(bufnr) then
							return
						end

						stop_spinner()

						if not ok then
							utils.notify_error('ETChat error: ' .. tostring(resp_or_err))
							utils.close_win(win_id)
							return
						end

						local parsed = utils.parse_response(resp_or_err)
						stream_text_to_popup(parsed, function(acc)
							if not vim.api.nvim_buf_is_valid(bufnr) then
								return
							end
							local live_lines = vim.list_extend(vim.deepcopy(processing_lines), vim.split(acc, '\n', { plain = true }))
							utils.set_popup_lines(bufnr, live_lines)
							resize_chat_popup(win_id, #live_lines)
							scroll_chat_to_bottom(win_id, bufnr)
						end, function(final_text)
							if not vim.api.nvim_buf_is_valid(bufnr) then
								return
							end

							if state.get_mode() == 'chat' then
								state.add_to_temp_history('assistant', final_text)
							end

							local final_lines = vim.list_extend(vim.deepcopy(processing_lines), vim.split(final_text, '\n', { plain = true }))
							table.insert(final_lines, '')
							table.insert(final_lines, '> ')
							utils.set_popup_lines(bufnr, final_lines)
							resize_chat_popup(win_id, #final_lines)
							scroll_chat_to_bottom(win_id, bufnr)
							vim.api.nvim_set_option_value('buftype', 'acwrite', { buf = bufnr })
							vim.api.nvim_set_option_value('modifiable', true, { buf = bufnr })
							vim.bo[bufnr].modified = true
							mode = 'input'
							state.set_ui_status('input')
							vim.keymap.set('n', 'q', cancel, { buffer = bufnr, silent = true })
							pcall(vim.api.nvim_set_current_win, win_id)
							pcall(vim.api.nvim_win_set_cursor, win_id, { vim.api.nvim_buf_line_count(bufnr), 2 })
							pcall(vim.cmd, 'stopinsert')
						end)
					end)
				end,
			})

			vim.keymap.set('n', 'q', cancel, { buffer = bufnr, silent = true })
			vim.keymap.set('i', 'q', cancel, { buffer = bufnr, silent = true })
		end,
	})
end

return M
