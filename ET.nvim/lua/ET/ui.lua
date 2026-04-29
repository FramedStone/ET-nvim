local M = {}
local Layout = require('nui.layout')
local Popup = require('nui.popup')
local Menu = require('nui.menu')
local event = require('nui.utils.autocmd').event

-- Track active components for VimResized auto-resize
M._active_components = {}

local function register_component(component)
	M._active_components[component] = true
end

local function unregister_component(component)
	M._active_components[component] = nil
end

-- Auto-resize all active components on terminal resize
vim.api.nvim_create_autocmd('VimResized', {
	callback = function()
		for comp, _ in pairs(M._active_components) do
			-- Layout has is_mounted(), Popup has winid
			local is_valid = false
			if comp.is_mounted then
				is_valid = comp:is_mounted()
			elseif comp.winid then
				is_valid = vim.api.nvim_win_is_valid(comp.winid)
			end

			if is_valid then
				local ok, _ = pcall(comp.update_layout, comp)
				if not ok then
					unregister_component(comp)
				end
			else
				unregister_component(comp)
			end
		end
	end,
})

function M.create_popup(title, width, height)
	width = width or '80%'
	height = height or '70%'

	local popup = Popup({
		enter = true,
		focusable = true,
		position = '50%',
		size = { width = width, height = height },
		border = {
			style = 'rounded',
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
	register_component(popup)

	popup:on(event.BufLeave, function()
		unregister_component(popup)
	end, { once = true })

	return popup
end

function M.create_menu(title, items, on_submit, width, height)
	width = width or '50%'
	height = height or '40%'

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
			-- Preserve custom fields (e.g., _res) by passing them to Menu.item
			local item_data = { text = item.text }
			for k, v in pairs(item) do
				if k ~= 'text' and k ~= 'separator' then
					item_data[k] = v
				end
			end
			table.insert(menu_items, Menu.item(item.text, item_data))
		end
	end

	local menu = Menu({
		position = '50%',
		size = { width = width, height = height },
		border = {
			style = 'rounded',
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
				on_submit(item)
			end
		end,
	})

	menu:mount()
	register_component(menu)

	menu:on(event.BufLeave, function()
		unregister_component(menu)
	end, { once = true })

	return menu
end

--- Creates a layout with multiple nui components arranged vertically.
--- @param width? number|string layout width (default: '90%')
--- @param height? number|string layout height (default: '85%')
--- @param boxes {component: any, size?: number, initial_focus?: boolean}[] array of {component, size} where size is percentage
--- @param direction? string 'col' or 'row'
--- @return nui.layout
function M.create_layout(width, height, boxes, direction)
	width = width or '90%'
	height = height or '85%'

	local function build_boxes(box_configs)
		local box_children = {}
		local components = {}
		for _, box_config in ipairs(box_configs) do
			if box_config.dir then
				local children = {}
				local child_components = {}
				for i, child in ipairs(box_config) do
					if type(child) == 'table' and child.component then
						local component = child.component
						local size = child.size or math.floor(100 / #box_config)
						size = type(size) == 'number' and size .. '%' or size
						table.insert(children, Layout.Box(component, { size = size }))
						table.insert(child_components, component)
					end
				end
				for _, c in ipairs(child_components) do
					table.insert(components, c)
				end
				local size = box_config.size or math.floor(100 / #box_configs)
				size = type(size) == 'number' and size .. '%' or size
				table.insert(box_children, Layout.Box(children, { dir = box_config.dir, size = size }))
			else
				local component = box_config.component
				local size = box_config.size or math.floor(100 / #box_configs)
				size = type(size) == 'number' and size .. '%' or size
				table.insert(box_children, Layout.Box(component, { size = size }))
				table.insert(components, component)
			end
		end
		return box_children, components
	end

	local box_children, components = build_boxes(boxes)

	local layout = Layout({
		position = '50%',
		size = { width = width, height = height },
		relative = 'editor',
	}, Layout.Box(box_children, { dir = direction }))

	local current_index = 1
	local function focus_next()
		current_index = current_index % #components + 1
		local comp = components[current_index]
		vim.api.nvim_set_current_win(comp.winid)
	end

	local function focus_prev()
		current_index = current_index > 1 and current_index - 1 or #components
		local comp = components[current_index]
		vim.api.nvim_set_current_win(comp.winid)
	end

	if #components > 1 then
		for _, comp in ipairs(components) do
			comp:map('n', '<TAB>', focus_next, { noremap = true, nowait = true })
			comp:map('n', '<S-TAB>', focus_prev, { noremap = true, nowait = true })
		end
	end

	layout:mount()
	register_component(layout)

	local function find_initial_focus(box_list)
		for _, box in ipairs(box_list) do
			if box.initial_focus and box.component and box.component.winid then
				return box
			end
			if box.dir and box[1] then
				local nested = find_initial_focus(box)
				if nested then
					return nested
				end
			end
		end
		return nil
	end

	local function set_initial_focus()
		local target_box = find_initial_focus(boxes)
		if not target_box and boxes[1] and boxes[1].dir then
			target_box = boxes[1][2] or boxes[1][1]
		end
		if not target_box and boxes[1] and boxes[1].component then
			target_box = boxes[1]
		end
		if target_box and target_box.component and target_box.component.winid then
			vim.api.nvim_set_current_win(target_box.component.winid)
		end
	end
	vim.defer_fn(set_initial_focus, 0)

	return layout, components, boxes
end

return M
