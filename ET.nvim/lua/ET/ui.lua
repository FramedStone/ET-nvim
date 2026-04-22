local M = {}
local Popup = require('nui.popup')
local Input = require('nui.input')
local Menu = require('nui.menu')

function M.create_popup(title, width, height)
	width = width or 50
	height = height or 10

	local popup = Popup({
		enter = true,
		focusable = true,
		position = '50%',
		size = { width = width, height = height },
		border = {
			style = 'single',
			text = {
				top = title,
				top_align = 'left',
			},
		},
		buf_options = {
			buftype = '',
			modifiable = true,
			readonly = false,
		},
	})

	popup:mount()
	return popup
end

function M.create_input(title, width, height, placeholder, on_submit)
	width = width or 50
	height = height or 1

	local input = Input({
		position = '50%',
		size = { width = width, height = height },
		border = {
			style = 'single',
			text = {
				top = title,
				top_align = 'left',
			},
		},
		{
			default_value = placeholder,
			on_submit = on_submit,
		},
	})

	input:mount()
	return input
end

function M.create_menu(title, items, on_submit, width, height)
	width = width or 50
	height = height or 5

	local menu_items = {}
	for _, item in ipairs(items) do
		if item.separator then
			table.insert(
				menu_items,
				Menu.separator(item.text, {
					char = item.char or '-',
					text_align = item.text_align or 'right',
				})
			)
		else
			table.insert(menu_items, Menu.item(item.text))
		end
	end

	local menu = Menu({
		position = '50%',
		size = { width = width, height = height },
		border = {
			style = 'single',
			text = {
				top = title,
				top_align = 'center',
			},
		},
		win_options = {
			winhighlight = 'Normal:Normal,FloatBorder:Normal',
		},
	}, {
		lines = menu_items,
		max_width = 20,
		keymap = {
			focus_next = { 'j' },
			focus_prev = { 'k' },
			submit = { ':wq', '<CR>' },
		},
		on_close = function() end,
		on_submit = function(item)
			if on_submit then
				on_submit(item.text)
			end
		end,
	})

	menu:mount()
	return menu
end

return M
