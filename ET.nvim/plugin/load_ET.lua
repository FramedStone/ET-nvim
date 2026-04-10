local config = require('ET.config')
local popup = require('plenary.popup')
local provider = require('ET.provider.omlx')

local function is_endpoint_accessible(endpoint)
	local url = endpoint .. '/models'
	local response = vim.fn.system({
		'curl',
		'-sS',
		'--max-time',
		'5',
		url,
	})

	if vim.v.shell_error ~= 0 then
		return false, response
	end

	return true
end

local function is_api_key_accessible(endpoint, api_key)
	local url = endpoint .. '/models'
	local response = vim.fn.system({
		'curl',
		'-sS',
		'--max-time',
		'5',
		'-H',
		'Authorization: Bearer ' .. api_key,
		url,
	})

	if vim.v.shell_error ~= 0 then
		return false, response
	end

	local ok, decoded = pcall(vim.fn.json_decode, response)
	if ok and decoded and decoded.error then
		local err = decoded.error
		return false, err.message or vim.fn.json_encode(err)
	end

	return true
end

local function create_input_popup(title, default_value, on_submit)
	popup.create('', {
		title = title,
		minwidth = 40,
		line = math.floor(((vim.o.lines - 1) / 2) - 1),
		col = math.floor((vim.o.columns - 40) / 2),
		border = {},
		enter = true,
		finalize_callback = function(win_id, bufnr)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { default_value or '' })

			local function submit()
				local input = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1] or ''

				if vim.api.nvim_win_is_valid(win_id) then
					vim.api.nvim_win_close(win_id, true)
				end

				vim.schedule(function()
					on_submit(input)
				end)
			end

			local function cancel()
				if vim.api.nvim_win_is_valid(win_id) then
					vim.api.nvim_win_close(win_id, true)
				end
			end

			vim.keymap.set('n', '<CR>', submit, { buffer = bufnr, silent = true })
			vim.keymap.set('n', 'q', cancel, { buffer = bufnr, silent = true })
			vim.keymap.set('i', '<CR>', submit, { buffer = bufnr, silent = true })
			vim.keymap.set('i', 'q', cancel, { buffer = bufnr, silent = true })
		end,
	})
end

local function Onboard()
	local loaded_config = config.load_config()
	local loaded_omlx = loaded_config and loaded_config.omlx or {}
	local initial_endpoint = loaded_omlx.endpoint or 'http://localhost:8000/v1'
	local initial_api_key = loaded_omlx.api_key or ''

	local function prompt_api_key(default_api_key, endpoint)
		create_input_popup('oMLX api_key (if any)', default_api_key, function(api_key)
			if api_key == '' then
				return
			end

			local ok, err = is_api_key_accessible(endpoint, api_key)
			if not ok then
				vim.notify('Invalid oMLX api_key: ' .. tostring(err), vim.log.levels.ERROR)
				prompt_api_key(api_key, endpoint)
				return
			end

			config.set_config({
				omlx = {
					api_key = api_key,
				},
			})

			vim.schedule(function()
				vim.cmd('stopinsert')
			end)
		end)
	end

	local function prompt_endpoint(default_endpoint)
		create_input_popup('oMLX endpoint', default_endpoint or initial_endpoint, function(input)
			if input == '' then
				return
			end

			local ok, err = is_endpoint_accessible(input)
			if not ok then
				vim.notify('Invalid oMLX endpoint: ' .. tostring(err), vim.log.levels.ERROR)
				prompt_endpoint(input)
				return
			end

			config.set_config({
				omlx = {
					endpoint = input,
				},
			})

			prompt_api_key(initial_api_key, input)
		end)
	end

	prompt_endpoint(initial_endpoint)
end

local function ensure_default_model()
	local loaded_config = config.load_config()
	if loaded_config.omlx == nil or (loaded_config.omlx.model ~= nil and loaded_config.omlx.model ~= '') then
		return
	end

	local ok, models = pcall(provider.list_models)
	if ok and models and models[1] then
		config.set_config({
			omlx = {
				model = models[1],
			},
		})
	end
end

vim.api.nvim_create_user_command('ETOnboard', function()
	Onboard()
end, { desc = 'Run ET onboarding flow' })

vim.api.nvim_create_autocmd('UIEnter', {
	callback = function()
		local loaded_config = config.load_config()
		if vim.tbl_isempty(loaded_config) or loaded_config.omlx == nil then
			Onboard()
		end

		vim.schedule(ensure_default_model)
	end,
})
