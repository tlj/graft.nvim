---@class graft.UI.StatusWindow
---@field active boolean Whether the status window is currently active
---@field bufnr number|nil The buffer number for the status window
---@field winnr number|nil The window number for the status window
---@field messages string[] List of status messages

local M = {
	active = false,
	bufnr = nil,
	winnr = nil,
	messages = {},
}

-- Get the graft instance
local graft = require("graft")

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
	local width = math.min(80, math.floor(vim.o.columns * 0.8))
	local height = math.min(20, math.floor(vim.o.lines * 0.5))
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
		title = " Graft Plugin Status ",
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

	-- Register hook for when operations complete
	graft.register_hook("post_sync", function()
		M.add_message("All operations complete.")
		vim.defer_fn(function() M.close() end, 2000)
	end)

	return M.winnr
end

-- Add a message to the status window
---@param msg string The message to add
function M.add_message(msg)
	if not M.active or not M.bufnr or not M.winnr then
		return
	end

	-- Add message to the list
	table.insert(M.messages, msg)

	-- Update the buffer content
	vim.api.nvim_buf_set_lines(M.bufnr, 0, -1, false, M.messages)

	-- Scroll to the bottom
	if vim.api.nvim_win_is_valid(M.winnr) then
		vim.api.nvim_win_set_cursor(M.winnr, { #M.messages, 0 })
	end

	-- Force a redraw to update the UI
	vim.cmd.redraw()
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
	local width = math.min(80, math.floor(vim.o.columns * 0.8))
	local height = math.min(20, math.floor(vim.o.lines * 0.5))
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
		title = " Graft Plugin Status ",
		title_pos = "center",
	}

	-- Create the window
	M.winnr = vim.api.nvim_open_win(M.bufnr, true, opts) -- Set focus to true
	vim.wo[M.winnr].winblend = 10
	vim.wo[M.winnr].cursorline = false

	-- Set active flag
	M.active = true

	-- Update the buffer with existing messages
	if #M.messages > 0 then
		vim.api.nvim_buf_set_lines(M.bufnr, 0, -1, false, M.messages)

		-- Scroll to the bottom
		vim.api.nvim_win_set_cursor(M.winnr, { #M.messages, 0 })
	end

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

return M
