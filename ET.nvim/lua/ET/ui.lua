local M = {}
local Layout = require('nui.layout')
local Popup = require('nui.popup')
local Menu = require('nui.menu')
local Input = require('nui.input')
local Tree = require('nui.tree')
local Line = require('nui.line')
local event = require('nui.utils.autocmd').event

-- Trim leading/trailing whitespace from a string
function M.trim(str)
	return (str or ''):gsub('^%s*(.-)%s*$', '%1')
end

-- Focus a popup's window and move cursor to the last line
function M.focus_last_line(popup)
	popup = popup.winid and popup or (popup and popup.popup or nil) -- accept popup directly or opts table
	if not popup or not popup.winid then
		return
	end
	vim.schedule(function()
		if popup.winid then
			vim.api.nvim_set_current_win(popup.winid)
			local last = vim.api.nvim_buf_line_count(popup.bufnr)
			vim.api.nvim_win_set_cursor(popup.winid, { last, 0 })
		end
	end)
end

-- Prompt user for a numeric count, then call callback(count)
function M.prompt_count(callback, default)
	default = default or 5
	local input = Input({
		relative = 'cursor',
		position = { row = 1, col = 0 },
		size = 25,
		zindex = 200,
		border = { style = 'rounded', text = { top = '[Result Count]', top_align = 'left' } },
		win_options = { winhighlight = 'Normal:Normal,FloatBorder:Normal' },
	}, {
		prompt = 'count: ',
		default_value = tostring(default),
		on_submit = function(value)
			local count = tonumber(value) or default
			if count < 1 then count = default end
			callback(count)
		end,
	})
	input:map('n', '<Esc>', function()
		input:unmount()
	end, { noremap = true, nowait = true })
	input:mount()
end

-- Bind standard save/close keymaps to a nui popup
-- on_save: called on :w<CR> or :wq<CR>
-- on_close: called on q or :q<CR> (defaults to popup:unmount())
function M.bind_save_close_keys(popup, on_save, on_close)
	on_close = on_close or function() popup:unmount() end
	popup:map('n', ':w<CR>', on_save, { noremap = true, nowait = true })
	popup:map('n', ':wq<CR>', on_save, { noremap = true, nowait = true })
	popup:map('n', 'q', on_close, { noremap = true, nowait = true })
	popup:map('n', ':q<CR>', on_close, { noremap = true, nowait = true })
end

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
		relative = 'editor',
		position = '50%',
		zindex = 200,
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
		win_options = {
			relativenumber = true,
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

	local function build_boxes_impl(box_configs)
		local box_children = {}
		local components = {}
		for _, box_config in ipairs(box_configs) do
			local size = box_config.size or math.floor(100 / #box_configs)
			size = type(size) == 'number' and size .. '%' or size
			if box_config.dir then
				local sub_children, sub_components = build_boxes_impl(box_config)
				for _, c in ipairs(sub_components) do
					table.insert(components, c)
				end
				table.insert(box_children, Layout.Box(sub_children, { dir = box_config.dir, size = size }))
			elseif box_config.component then
				table.insert(box_children, Layout.Box(box_config.component, { size = size }))
				if box_config.focusable ~= false then
					table.insert(components, box_config.component)
				end
			end
		end
		return box_children, components
	end

	local box_children, components = build_boxes_impl(boxes)

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

	-- Set initial focus: respect initial_focus hint, fall back to first focusable component
	vim.defer_fn(function()
		local target = nil
		-- Walk box configs recursively to find the one marked initial_focus
		local function find_initial(box_list)
			for _, box in ipairs(box_list) do
				if box.initial_focus and box.component and box.component.winid then
					target = box.component
					return true
				end
				if box.dir and box[1] then
					if find_initial(box) then return true end
				end
			end
		end
		find_initial(boxes)
		target = target or components[1]
		if target and target.winid then
			vim.api.nvim_set_current_win(target.winid)
		end
	end, 0)

	return layout, components, boxes
end

---- Internal helper: toggle a tree node (expand/collapse) if it has children.
--- Returns true if the node was toggled (it has children), false if it's a leaf.
local function toggle_tree_node(tree, node)
	if node and node:has_children() then
		if node:is_expanded() then
			node:collapse()
		else
			node:expand()
		end
		tree:render()
		return true
	end
	return false
end

--- Creates a NuiTree on a popup's buffer with default node rendering and keymaps.
--- @param popup table the nui Popup instance to render the tree into
--- @param placeholder string text shown before results are loaded
--- @param opts? table optional config
--- @param opts.prepare_node? fun(node: any): any custom node formatter
--- @param opts.keymaps? table<string, function|false> key overrides (false to disable)
--- @param opts.on_open? fun(node: NuiTree.Node): boolean called on <CR>/l BEFORE toggle; return true to suppress toggle
--- @return NuiTree tree
function M.create_tree(popup, placeholder, opts)
	opts = opts or {}

	local prepare_node = opts.prepare_node or function(node)
		local line = Line()
		if node:has_children() then
			local icon = node:is_expanded() and '  ' or '  '
			line:append(icon, 'SpecialChar')
			line:append(node.text, 'Title')
		elseif node._is_child then
			if node._url then
				line:append(node.text, 'Comment')
			else
				line:append(node.text, 'Normal')
			end
		else
			line:append(node.text)
		end
		return line
	end

	local tree = Tree({
		bufnr = popup.bufnr,
		nodes = { Tree.Node({ text = placeholder }) },
		prepare_node = prepare_node,
	})

	-- Shared handler for <CR> and l: try on_open first, fall back to toggle
	local function activate_node()
		local node = tree:get_node()
		if not node then return end
		-- on_open gets first chance; return true means "handled, don't toggle"
		if opts.on_open and opts.on_open(node) then
			return
		end
		toggle_tree_node(tree, node)
	end

	local keymaps = opts.keymaps or {}

	if keymaps.h ~= false then
		local handler = keymaps.h or activate_node
		popup:map('n', 'h', handler, { noremap = true, nowait = true })
	end

	if keymaps.l ~= false then
		popup:map('n', 'l', keymaps.l or activate_node, { noremap = true, nowait = true })
	end

	if keymaps.j ~= false then
		local handler = keymaps.j or 'j'
		popup:map('n', 'j', handler, { noremap = true, nowait = true })
	end

	if keymaps.k ~= false then
		local handler = keymaps.k or 'k'
		popup:map('n', 'k', handler, { noremap = true, nowait = true })
	end

	if keymaps['<CR>'] ~= false then
		popup:map('n', '<CR>', keymaps['<CR>'] or activate_node, { noremap = true, nowait = true })
	end

	if keymaps['<Esc>'] ~= false then
		local handler = keymaps['<Esc>'] or function() end
		popup:map('n', '<Esc>', handler, { noremap = true, nowait = true })
	end

	tree:render()

	return tree
end

return M
