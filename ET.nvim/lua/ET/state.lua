local M = {}

local state = {
	mode = 'chat',
	current_message = nil,
	active_chat_win = nil,
	active_chat_buf = nil,
	temp_history = {},
	raw_tool_results = {},
	last_response = nil,
	ui_status = 'idle',
}

function M.get_state()
	return state
end

function M.reset_state()
	state.mode = 'chat'
	state.current_message = nil
	state.active_chat_win = nil
	state.active_chat_buf = nil
	state.temp_history = {}
	state.raw_tool_results = {}
	state.last_response = nil
	state.ui_status = 'idle'
end

function M.update_state(key, value)
	state[key] = value
end

function M.add_to_temp_history(role, content)
	table.insert(state.temp_history, {
		role = role,
		content = content,
		timestamp = os.time(),
	})
end

function M.add_raw_tool_result(tool_name, payload)
	table.insert(state.raw_tool_results, {
		tool = tool_name,
		payload = payload,
		timestamp = os.time(),
	})
end

function M.set_mode(mode)
	state.mode = mode
end

function M.get_mode()
	return state.mode
end

function M.set_ui_status(status)
	state.ui_status = status
end

function M.get_ui_status()
	return state.ui_status
end

function M.set_active_chat_window(win_id, bufnr)
	state.active_chat_win = win_id
	state.active_chat_buf = bufnr
end

function M.get_active_chat_window()
	return state.active_chat_win, state.active_chat_buf
end

return M
