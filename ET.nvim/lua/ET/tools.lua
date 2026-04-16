local M = {}
local fzf = require('fzf-lua')

function M.select_files()
	fzf.files({
		actions = {
			['default'] = function(selected)
				-- Extract the path (strips icons/formatting)
				local file = fzf.path.entry_to_file(selected[1])
				-- TODO: parse into Agent
				return file.path
			end,
		},
	})
end

-- Copy line of codes highlighted using visual mode with absolute path
function M.select_line_of_codes(opts)
	local start_line = opts.line1
	local end_line = opts.line2
	local bufname = vim.api.nvim_buf_get_name(0)
	local abs = vim.fn.fnamemodify(bufname, ':p')
	local anchor
	anchor = string.format('#L%d-L%d', start_line, end_line)

	-- TODO: parse into Agent
	local out = abs .. anchor
end

-- Receive filename(s), return absolute path(s)
function M.find_files(filenames)
	local results = {}
	for _, filename in ipairs(filenames) do
		local output = vim.fn.system(string.format('find . -name "%s"', filename))
		if output and output ~= '' then
			for _, path in ipairs(vim.split(output, '\n')) do
				if path ~= '' then
					local abs_path = vim.fn.fnamemodify(path, ':p')
					table.insert(results, abs_path)
				end
			end
		end
	end
	return results
end

function M.read_file(filepath)
	local lines = vim.fn.readfile(filepath)
	if lines then
		return table.concat(lines, '\n')
	end
end

return M
