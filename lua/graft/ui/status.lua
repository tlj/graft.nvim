---@class graft.UI.PluginStatus
---@field name string Plugin name
---@field repo string Plugin repository
---@field status string Current status (pending, installing, updating, removing, complete, failed)
---@field message string Additional status message

---@class graft.UI.StatusWindow
---@field active boolean Whether the status window is currently active
---@field bufnr number|nil The buffer number for the status window
---@field winnr number|nil The window number for the status window
---@field messages string[] List of status messages
---@field plugin_statuses table<string, graft.UI.PluginStatus> Table of plugin statuses indexed by plugin name
---@field header_lines number Number of header lines in the status window
---@field footer_lines number Number of footer lines in the status window
---@field auto_close boolean Whether to auto-close the window when all operations complete

local M = {
	active = false,
	bufnr = nil,
	winnr = nil,
	messages = {},
	plugin_statuses = {},
	header_lines = 3,
	footer_lines = 2,
	auto_close = true,
}

-- Get the graft instance
local graft = require("graft")

-- Calculate the optimal window size based on content
---@return number width, number height
local function calculate_window_size()
	-- Base size for empty window
	local min_width = 80
	local min_height = 10
	
	-- Calculate width based on plugin names
	local content_width = min_width
	for _, status in pairs(M.plugin_statuses) do
		local line_length = #status.repo + #status.status + 15 -- Add padding for formatting
		content_width = math.max(content_width, line_length)
	end
	
	-- Add some padding
	content_width = content_width + 4
	
	-- Calculate height based on number of plugins plus header/footer
	local content_height = M.header_lines + #vim.tbl_keys(M.plugin_statuses) + M.footer_lines
	content_height = math.max(min_height, content_height)
	
	-- Respect screen boundaries
	local width = math.min(content_width, math.floor(vim.o.columns * 0.9))
	local height = math.min(content_height, math.floor(vim.o.lines * 0.8))
	
	return width, height
end

-- Create a floating window for displaying status messages
function M.create()
	if M.active then
		return
	end

	-- Create a new buffer for the status window
	M.bufnr = vim.api.nvim_create_buf(false, true)
	vim.bo[M.bufnr].buftype = "nofile"
	vim.bo[M.bufnr].bufhidden = "wipe"
	vim.bo[M.bufnr].swapfile = false
	vim.bo[M.bufnr].filetype = "graft-status"

	-- Calculate window size and position
	local width, height = calculate_window_size()
	local col = math.floor((vim.o.columns - width) / 2)
	local row = math.floor((vim.o.lines - height) / 2)

	-- Window options
	local opts = {
		relative = "editor",
		width = width,
		height = height,
		col = col,
		row = row,
		style = "minimal",
		border = "rounded",
		title = " Graft Plugin Manager ",
		title_pos = "center",
	}

	-- Create the window
	M.winnr = vim.api.nvim_open_win(M.bufnr, false, opts)
	vim.wo[M.winnr].winblend = 10
	vim.wo[M.winnr].cursorline = false

	-- Set up keymaps to close the window with ESC or q
	vim.api.nvim_buf_set_keymap(
		M.bufnr,
		"n",
		"q",
		":lua require('graft.ui.status').close()<CR>",
		{ noremap = true, silent = true }
	)
	vim.api.nvim_buf_set_keymap(
		M.bufnr,
		"n",
		"<Esc>",
		":lua require('graft.ui.status').close()<CR>",
		{ noremap = true, silent = true }
	)

	-- Set active flag
	M.active = true
	M.messages = {}
	
	-- Initialize the UI
	M.update_display()

	-- Register hook for when operations complete
	graft.register_hook("post_sync", function()
		M.add_message("All operations complete.")
		if M.auto_close then
			vim.defer_fn(function() M.close() end, 2000)
		end
	end)

	return M.winnr
end

-- Update the status display with current plugin statuses
function M.update_display()
	if not M.active or not M.bufnr then
		return
	end
	
	local lines = {}
	
	-- Header
	table.insert(lines, "Graft Plugin Operations")
	table.insert(lines, string.rep("─", 78))
	table.insert(lines, "Plugin                                  Status              Message")
	
	-- Sort plugins by name for consistent display
	local sorted_plugins = {}
	for _, status in pairs(M.plugin_statuses) do
		table.insert(sorted_plugins, status)
	end
	table.sort(sorted_plugins, function(a, b) return a.repo < b.repo end)
	
	-- Plugin statuses
	for _, status in ipairs(sorted_plugins) do
		local repo_display = status.repo
		if #repo_display > 40 then
			repo_display = "..." .. repo_display:sub(-37)
		end
		
		local status_display = status.status
		local status_color = ""
		
		if status.status == "complete" then
			status_color = "%#DiffAdd#"
		elseif status.status == "failed" then
			status_color = "%#DiffDelete#"
		elseif status.status == "installing" or status.status == "updating" or status.status == "removing" then
			status_color = "%#DiffChange#"
		end
		
		local line = string.format("%-40s %s%-18s%s %s", 
			repo_display, 
			status_color, 
			status_display, 
			"%#Normal#",
			status.message or "")
		
		table.insert(lines, line)
	end
	
	-- Footer with messages
	if #M.messages > 0 then
		table.insert(lines, "")
		table.insert(lines, "Recent messages:")
		
		-- Only show last few messages to avoid cluttering
		local start_idx = math.max(1, #M.messages - 5)
		for i = start_idx, #M.messages do
			table.insert(lines, "  " .. M.messages[i])
		end
	end
	
	-- Update the buffer content
	vim.api.nvim_buf_set_lines(M.bufnr, 0, -1, false, lines)
	
	-- Resize window if needed
	if M.winnr and vim.api.nvim_win_is_valid(M.winnr) then
		local width, height = calculate_window_size()
		vim.api.nvim_win_set_config(M.winnr, {
			width = width,
			height = height,
			col = math.floor((vim.o.columns - width) / 2),
			row = math.floor((vim.o.lines - height) / 2),
		})
	end
	
	-- Force a redraw to update the UI
	vim.cmd.redraw()
end

-- Add a message to the status window
---@param msg string The message to add
function M.add_message(msg)
	if not M.bufnr then
		return
	end

	-- Add message to the list
	table.insert(M.messages, msg)
	
	-- Limit message history
	if #M.messages > 20 then
		table.remove(M.messages, 1)
	end

	-- Update the display
	if M.active then
		M.update_display()
	end
end

-- Set or update the status of a plugin
---@param repo string The plugin repository (user/repo)
---@param status string The status (pending, installing, updating, removing, complete, failed)
---@param message? string Optional message
function M.set_plugin_status(repo, status, message)
	if not repo or repo == "" then
		return
	end
	
	-- Create or update the plugin status
	M.plugin_statuses[repo] = M.plugin_statuses[repo] or { repo = repo, name = repo:match("[^/]+$"), status = "pending", message = "" }
	M.plugin_statuses[repo].status = status
	
	if message then
		M.plugin_statuses[repo].message = message
	end
	
	-- Update the display if window is active
	if M.active then
		M.update_display()
	end
	
	-- Check if all operations are complete
	if status == "complete" or status == "failed" then
		local all_complete = true
		for _, plugin_status in pairs(M.plugin_statuses) do
			if plugin_status.status ~= "complete" and plugin_status.status ~= "failed" then
				all_complete = false
				break
			end
		end
		
		if all_complete and M.auto_close then
			M.add_message("All operations complete.")
			vim.defer_fn(function() 
				if M.active then
					M.close()
				end
			end, 3000)
		end
	end
end

-- Check if any plugins have the given status
---@param status string The status to check for
---@return boolean
function M.has_status(status)
	for _, plugin_status in pairs(M.plugin_statuses) do
		if plugin_status.status == status then
			return true
		end
	end
	return false
end

-- Reopen the status window with existing messages
function M.reopen()
	if M.active then
		return
	end

	-- Create a new buffer if needed
	if not M.bufnr or not vim.api.nvim_buf_is_valid(M.bufnr) then
		M.bufnr = vim.api.nvim_create_buf(false, true)
		vim.bo[M.bufnr].buftype = "nofile"
		vim.bo[M.bufnr].bufhidden = "wipe"
		vim.bo[M.bufnr].swapfile = false
		vim.bo[M.bufnr].filetype = "graft-status"
	end

	-- Calculate window size and position
	local width, height = calculate_window_size()
	local col = math.floor((vim.o.columns - width) / 2)
	local row = math.floor((vim.o.lines - height) / 2)

	-- Window options
	local opts = {
		relative = "editor",
		width = width,
		height = height,
		col = col,
		row = row,
		style = "minimal",
		border = "rounded",
		title = " Graft Plugin Manager ",
		title_pos = "center",
	}

	-- Create the window
	M.winnr = vim.api.nvim_open_win(M.bufnr, true, opts) -- Set focus to true
	vim.wo[M.winnr].winblend = 10
	vim.wo[M.winnr].cursorline = false

	-- Set active flag
	M.active = true

	-- Update the display
	M.update_display()

	-- Set up keymaps to close the window with ESC or q
	vim.api.nvim_buf_set_keymap(
		M.bufnr,
		"n",
		"q",
		":lua require('graft.ui.status').close()<CR>",
		{ noremap = true, silent = true }
	)
	vim.api.nvim_buf_set_keymap(
		M.bufnr,
		"n",
		"<Esc>",
		":lua require('graft.ui.status').close()<CR>",
		{ noremap = true, silent = true }
	)

	return M.winnr
end

-- Close the status window
function M.close()
	if not M.active then
		return
	end

	if M.winnr and vim.api.nvim_win_is_valid(M.winnr) then
		vim.api.nvim_win_close(M.winnr, true)
	end

	-- Keep the buffer and messages for reuse
	M.active = false
	M.winnr = nil
end

-- Reset all plugin statuses
function M.reset()
	M.plugin_statuses = {}
	M.messages = {}
	
	if M.active then
		M.update_display()
	end
end

return M
