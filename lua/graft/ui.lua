---@class graft.UI
local M = {}

-- Get the graft instance
local graft = require("graft")

-- Buffer and window handling
local buf = nil
local win = nil

-- Constants for window config
local WINDOW_WIDTH = 80
local WINDOW_HEIGHT = 40
local WINDOW_BORDER = "rounded"

-- Column configuration
local COLUMN_STATUS = 2
local COLUMN_REPO = 40 -- Width for repository names
local COLUMN_VERSION = 20 -- Width for version/branch info

-- Create a centered floating window
---@return number, number buffer number and window id
local function create_floating_window()
	-- Calculate window position
	local width = vim.api.nvim_get_option("columns")
	local height = vim.api.nvim_get_option("lines")

	local win_height = math.min(WINDOW_HEIGHT, height - 4)
	local win_width = math.min(WINDOW_WIDTH, width - 4)

	local row = math.floor((height - win_height) / 2)
	local col = math.floor((width - win_width) / 2)

	-- Create buffer
	local buffer = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_option(buffer, "bufhidden", "wipe")

	-- Window options
	local opts = {
		style = "minimal",
		relative = "editor",
		border = WINDOW_BORDER,
		width = win_width,
		height = win_height,
		row = row,
		col = col,
	}

	-- Create window
	local window = vim.api.nvim_open_win(buffer, true, opts)

	-- Set window options
	vim.api.nvim_win_set_option(window, "wrap", false)
	vim.api.nvim_win_set_option(window, "cursorline", true)

	-- Set buffer options
	vim.api.nvim_buf_set_option(buffer, "modifiable", false)
	vim.api.nvim_buf_set_option(buffer, "filetype", "graft-info")

	return buffer, window
end

-- Format plugin information
-- Utility function to truncate and pad strings
---@param str string
---@param width number
---@return string
local function format_column(str, width)
	if not str then
		str = ""
	end
	if #str > width then
		return string.sub(str, 1, width - 3) .. "..."
	end
	return str .. string.rep(" ", width - #str)
end

---@param plugin graft.Spec The plugin specification
---@return string A single formatted line for the plugin
local function format_plugin_info(plugin)
	-- Status column (fixed width)
	local status = graft.loaded[plugin.repo] and "✓" or " "
	local status_col = string.rep(" ", math.floor((COLUMN_STATUS - 1) / 2))
		.. status
		.. string.rep(" ", math.ceil((COLUMN_STATUS - 1) / 2))

	-- Repository column
	local repo_col = format_column("📦 " .. plugin.repo, COLUMN_REPO)

	-- Version/branch column
	local version = ""
	if plugin.branch then
		version = "(" .. plugin.branch .. ")"
	elseif plugin.tag then
		version = "(" .. plugin.tag .. ")"
	end
	local version_col = format_column(version, COLUMN_VERSION)

	return string.format("%s %s %s", status_col, repo_col, version_col)
end

-- Display plugin information
local function display_info()
	if buf and vim.api.nvim_buf_is_valid(buf) then
		vim.api.nvim_buf_delete(buf, { force = true })
	end

	-- Create new window
	buf, win = create_floating_window()

	-- Prepare content
	local lines = {}
	table.insert(lines, "🔌 Graft Plugins")
	table.insert(lines, string.rep("─", WINDOW_WIDTH - 2))

	-- Header
	local header = string.format(
		"%s %s %s",
		string.rep(" ", COLUMN_STATUS), -- Status column header is empty but maintains width
		format_column("📦 Repository", COLUMN_REPO),
		format_column("Version", COLUMN_VERSION)
	)
	table.insert(lines, header)
	table.insert(lines, string.rep("─", WINDOW_WIDTH - 2))

	-- Add plugin information
	local sorted_plugins = {}
	for _, plugin in pairs(graft.plugins) do
		table.insert(sorted_plugins, plugin)
	end
	table.sort(sorted_plugins, function(a, b) return a.repo < b.repo end)

	for _, plugin in ipairs(sorted_plugins) do
		table.insert(lines, format_plugin_info(plugin))
	end

	-- Set content
	vim.api.nvim_buf_set_option(buf, "modifiable", true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_buf_set_option(buf, "modifiable", false)

	-- Set keymaps
	local opts = { noremap = true, silent = true }
	vim.api.nvim_buf_set_keymap(buf, "n", "q", ":close<CR>", opts)
	vim.api.nvim_buf_set_keymap(buf, "n", "<Esc>", ":close<CR>", opts)
end

-- Create the info command
function M.setup()
	vim.api.nvim_create_user_command("GraftInfo", function() display_info() end, {})

	-- Register with graft
	if graft.register_hook then
		-- Register post_register hook to update UI when plugins change
		graft.register_hook("post_register", function()
			if buf and vim.api.nvim_buf_is_valid(buf) then
				display_info()
			end
		end)

		-- Register post_load hook to update UI when plugins are loaded
		graft.register_hook("post_load", function()
			if buf and vim.api.nvim_buf_is_valid(buf) then
				display_info()
			end
		end)
	end
end

return M
