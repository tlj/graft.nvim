local M = {}

function M.check()
	local health = vim.health

	health.start("graft.nvim")

	-- Check if graft can be required
	local has_graft, _ = pcall(require, "graft")
	if has_graft then
		health.ok("graft.nvim is installed")
	else
		health.error("graft.nvim is not installed")
	end

	-- Check if git is installed
	local git_exec = vim.fn.executable("git")
	if git_exec == 1 then
		health.ok("git is installed")
	else
		health.error("git is not installed")
	end
end

return M
