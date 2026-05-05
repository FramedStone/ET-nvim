local M = {}
local tools = require('ET.tools')

function M.review(edits, on_complete)
	if #edits == 0 then
		if on_complete then on_complete() end
		return
	end

	local saved_buf = vim.api.nvim_get_current_buf()
	local accepted = {}

	local function finish()
		pcall(vim.cmd, 'diffoff!')
		pcall(vim.cmd, 'only')

		if saved_buf and vim.api.nvim_buf_is_valid(saved_buf) then
			vim.api.nvim_set_current_buf(saved_buf)
		end

		local accepted_list = {}
		for i, edit in ipairs(edits) do
			if accepted[i] then
				table.insert(accepted_list, edit)
			end
		end

		if #accepted_list > 0 then
			tools.apply_edits(accepted_list)
		end

		vim.notify(string.format('ET.nvim: Accepted %d / %d edits', #accepted_list, #edits), vim.log.levels.INFO)
		if on_complete then on_complete() end
	end

	local function show_diff(index)
		if index < 1 then index = 1 end
		if index > #edits then
			finish()
			return
		end

		pcall(vim.cmd, 'diffoff!')
		pcall(vim.cmd, 'only')

		local edit = edits[index]

		local old_lines = vim.split(edit.old_content or '', '\n')
		if #old_lines == 0 then
			old_lines = { '' }
		end
		local new_lines = vim.split(edit.new_content or '', '\n')
		if #new_lines == 0 then
			new_lines = { '' }
		end

		local status = ''
		if accepted[index] == true then
			status = ' [accepted]'
		elseif accepted[index] == false then
			status = ' [declined]'
		end
		local title = string.format('[%d/%d] %s', index, #edits, edit.filepath)
		if edit.type == 'edit' then
			title = title .. '#L' .. edit.start_line .. '-L' .. edit.end_line
		end
		vim.notify(title .. status, vim.log.levels.INFO)

		local old_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(old_buf, 0, -1, false, old_lines)
		vim.bo[old_buf].bufhidden = 'wipe'

		local new_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(new_buf, 0, -1, false, new_lines)
		vim.bo[new_buf].bufhidden = 'wipe'

		vim.api.nvim_set_current_buf(old_buf)
		vim.cmd('rightbelow vsplit')
		local new_win = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(new_win, new_buf)

		vim.cmd('windo diffthis')
		vim.cmd('windo setlocal foldcolumn=0')

		bind_keys(old_buf, new_buf, index)
	end

	local function bind_keys(old_buf, new_buf, index)
		local function next_undecided(start)
			local next = start + 1
			while next <= #edits and accepted[next] ~= nil do
				next = next + 1
			end
			show_diff(next)
		end

		local function accept()
			accepted[index] = true
			for i = 1, index - 1 do
				if accepted[i] == nil then
					show_diff(i)
					return
				end
			end
			next_undecided(index)
		end

		local function decline()
			accepted[index] = false
			for i = 1, index - 1 do
				if accepted[i] == nil then
					show_diff(i)
					return
				end
			end
			next_undecided(index)
		end

		local function decline_all()
			for i = index, #edits do
				accepted[i] = false
			end
			finish()
		end

		local function set_kmap(buf, key, cb)
			vim.keymap.set('n', key, cb, { buffer = buf, noremap = true, nowait = true, silent = true })
		end

		set_kmap(old_buf, '<CR>', accept)
		set_kmap(new_buf, '<CR>', accept)
		set_kmap(old_buf, 'q', decline)
		set_kmap(new_buf, 'q', decline)
		set_kmap(old_buf, ':q<CR>', decline_all)
		set_kmap(new_buf, ':q<CR>', decline_all)
		set_kmap(old_buf, 'l', function() show_diff(index + 1) end)
		set_kmap(new_buf, 'l', function() show_diff(index + 1) end)
		set_kmap(old_buf, 'h', function() show_diff(index - 1) end)
		set_kmap(new_buf, 'h', function() show_diff(index - 1) end)
	end

	show_diff(1)
end

return M
