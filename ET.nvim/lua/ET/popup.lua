local M = {}
local Popup = require('nui.popup')
local Input = require('nui.input')

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

function M.create_menu(title, width, height, items) end

return M
