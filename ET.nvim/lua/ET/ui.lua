local M = {}
local Layout = require('nui.layout')
local Popup = require('nui.popup')
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

--- Creates a layout with multiple nui components arranged vertically.
--- @param width? number layout width (default: 80)
--- @param height? number layout height (default: 40)
--- @param boxes {component: any, size?: number}[] array of {component, size} where size is percentage
--- @return nui.layout
function M.create_layout(width, height, boxes, direction)
	width = width or 80
	height = height or 40

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

	local function resize_by(delta, resize_dir)
		local current_win = vim.api.nvim_get_current_win()

		local function find_parent_and_index(boxes_list, winid, parent)
			for i, box in ipairs(boxes_list) do
				if box.dir then
					-- Nested box: search within its children
					for j = 1, #box do
						local child = box[j]
						if child and child.component and child.component.winid == winid then
							return box, j
						end
					end
				elseif box.component and box.component.winid == winid then
					-- Direct component: return parent box and index
					return parent or boxes_list, i
				end
			end
			return nil, nil
		end

		local parent_box, child_index = find_parent_and_index(boxes, current_win, boxes)

		if not parent_box then
			for _, box in ipairs(boxes) do
				if box.dir then
					parent_box, child_index = find_parent_and_index(box, current_win, box)
					if parent_box then
						break
					end
				end
			end
		end

		if not parent_box or not child_index then
			return
		end

		local target = parent_box[child_index]
		if not target or not target.component then
			return
		end

		-- Horizontal resize: resize between two top-level boxes
		-- Left box (index 1): '>' expands left, '<' expands right
		-- Right box (index 2): '>' expands right, '<' expands left
		if resize_dir == 'horizontal' then
			-- Find which top-level box the current window is in
			local function find_top_level_index(boxes_list, winid)
				for i, box in ipairs(boxes_list) do
					if box.dir then
						for j = 1, #box do
							local child = box[j]
							if child and child.component and child.component.winid == winid then
								return i
							end
						end
					elseif box.component and box.component.winid == winid then
						return i
					end
				end
				return nil
			end

			local top_idx = find_top_level_index(boxes, current_win)
			if not top_idx then
				return
			end

			local main_target = boxes[top_idx]
			local main_other = boxes[top_idx % #boxes + 1]

			local delta_mult = (top_idx == 1) and 1 or -1
			-- Invert delta for right-side boxes so '>' expands the focused box
			local new_target_size = (main_target.size or 50) + (delta * delta_mult)
			local new_other_size = (main_other.size or 50) - (delta * delta_mult)

			new_target_size = math.max(10, math.min(90, new_target_size))
			new_other_size = math.max(10, math.min(90, new_other_size))

			main_target.size = new_target_size
			main_other.size = new_other_size
		else
			-- Vertical resize: resize within the parent box (nested layout)
			-- '+' expands focused box, '_' expands neighbor
			local other_index = (child_index % #parent_box) + 1
			local other = parent_box[other_index]

			local new_target_size = (target.size or 50) + delta
			local new_other_size = (other.size or 50) - delta

			new_target_size = math.max(10, math.min(90, new_target_size))
			new_other_size = math.max(10, math.min(90, new_other_size))

			target.size = new_target_size
			other.size = new_other_size
		end

		local new_box_children = build_boxes(boxes)
		layout:update(Layout.Box(new_box_children, { dir = direction }))
	end

	if #components > 1 then
		for _, comp in ipairs(components) do
			comp:map('n', '<TAB>', focus_next, { noremap = true })
			comp:map('n', '<S-TAB>', focus_prev, { noremap = true })
			comp:map('n', '>', function()
				resize_by(5, 'horizontal')
			end, { noremap = true, nowait = true })
			comp:map('n', '<', function()
				resize_by(-5, 'horizontal')
			end, { noremap = true, nowait = true })
			comp:map('n', '+', function()
				resize_by(5, 'vertical')
			end, { noremap = true, nowait = true })
			comp:map('n', '_', function()
				resize_by(-5, 'vertical')
			end, { noremap = true, nowait = true })
		end
	end

	layout:mount()
	local function set_initial_focus()
		if boxes[1] and boxes[1].dir then
			local target = boxes[1][2] or boxes[1][1]
			if target and target.component and target.component.winid then
				vim.api.nvim_set_current_win(target.component.winid)
			end
		elseif boxes[1] and boxes[1].component and boxes[1].component.winid then
			vim.api.nvim_set_current_win(boxes[1].component.winid)
		end
	end
	vim.defer_fn(set_initial_focus, 0)

	return layout, components, boxes
end

function M.rebind_keymaps(components, boxes, layout, opts)
	opts = opts or {}
	local on_submit = opts.on_submit

	if not components or #components == 0 then
		return
	end

	local function build_boxes(box_configs)
		local box_children = {}
		for _, box_config in ipairs(box_configs) do
			if box_config.dir then
				local children = {}
				for _, child in ipairs(box_config) do
					if type(child) == 'table' and child.component then
						local component = child.component
						local size = child.size or math.floor(100 / #box_config)
						size = type(size) == 'number' and size .. '%' or size
						table.insert(children, Layout.Box(component, { size = size }))
					end
				end
				local size = box_config.size or math.floor(100 / #box_configs)
				size = type(size) == 'number' and size .. '%' or size
				table.insert(box_children, Layout.Box(children, { dir = box_config.dir, size = size }))
			else
				local component = box_config.component
				local size = box_config.size or math.floor(100 / #box_configs)
				size = type(size) == 'number' and size .. '%' or size
				table.insert(box_children, Layout.Box(component, { size = size }))
			end
		end
		return box_children
	end

	local function find_parent_and_index(boxes_list, winid, parent)
		for i, box in ipairs(boxes_list) do
			if box.dir then
				for j = 1, #box do
					local child = box[j]
					if child and child.component and child.component.winid == winid then
						return box, j
					end
				end
			elseif box.component and box.component.winid == winid then
				return parent or boxes_list, i
			end
		end
		return nil, nil
	end

	local function resize_by(delta, resize_dir)
		local current_win = vim.api.nvim_get_current_win()
		local parent_box, child_index = find_parent_and_index(boxes, current_win, boxes)

		if not parent_box then
			for _, box in ipairs(boxes) do
				if box.dir then
					parent_box, child_index = find_parent_and_index(box, current_win, box)
					if parent_box then
						break
					end
				end
			end
		end

		if not parent_box or not child_index then
			return
		end

		local target = parent_box[child_index]
		if not target or not target.component then
			return
		end

		if resize_dir == 'horizontal' then
			local function find_top_level_index(boxes_list, winid)
				for i, box in ipairs(boxes_list) do
					if box.dir then
						for j = 1, #box do
							local child = box[j]
							if child and child.component and child.component.winid == winid then
								return i
							end
						end
					elseif box.component and box.component.winid == winid then
						return i
					end
				end
				return nil
			end

			local top_idx = find_top_level_index(boxes, current_win)
			if not top_idx then
				return
			end

			local main_target = boxes[top_idx]
			local main_other = boxes[top_idx % #boxes + 1]

			local delta_mult = (top_idx == 1) and 1 or -1
			local new_target_size = (main_target.size or 50) + (delta * delta_mult)
			local new_other_size = (main_other.size or 50) - (delta * delta_mult)

			new_target_size = math.max(10, math.min(90, new_target_size))
			new_other_size = math.max(10, math.min(90, new_other_size))

			main_target.size = new_target_size
			main_other.size = new_other_size
		else
			local other_index = (child_index % #parent_box) + 1
			local other = parent_box[other_index]

			local new_target_size = (target.size or 50) + delta
			local new_other_size = (other.size or 50) - delta

			new_target_size = math.max(10, math.min(90, new_target_size))
			new_other_size = math.max(10, math.min(90, new_other_size))

			target.size = new_target_size
			other.size = new_other_size
		end

		local new_box_children = build_boxes(boxes)
		layout:update(Layout.Box(new_box_children, { dir = 'row' }))
	end

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

	for _, comp in ipairs(components) do
		comp:map('n', '<TAB>', focus_next, { noremap = true })
		comp:map('n', '<S-TAB>', focus_prev, { noremap = true })
		comp:map('n', '>', function()
			resize_by(5, 'horizontal')
		end, { noremap = true, nowait = true })
		comp:map('n', '<', function()
			resize_by(-5, 'horizontal')
		end, { noremap = true, nowait = true })
		comp:map('n', '+', function()
			resize_by(5, 'vertical')
		end, { noremap = true, nowait = true })
		comp:map('n', '_', function()
			resize_by(-5, 'vertical')
		end, { noremap = true, nowait = true })
		if on_submit then
			comp:map('n', ':w<CR>', function()
				on_submit()
			end, { noremap = true })
		end
	end
end

return M
