---@class graft.Git.Sync
---@field install_plugins? boolean Install missing plugins (default: true)
---@field update_plugins? boolean Update all plugin submodules (default: false)
---@field remove_plugins? boolean Remove plugins which are no longer defined (default: false)

---@class graft.Git
local M = {}

-- Get the graft instance
local graft = require("graft")

-- Update status in neovim without user input
---@param msg string
local function show_status(msg)
	vim.cmd.redraw()
	vim.cmd.echo("'" .. msg .. "'")
end

---@param spec graft.Spec
---@return boolean
M.is_installed = function(spec)
	local ok, _ = pcall(require, spec.name)
	if ok then
		return true
	end

	if vim.fn.isdirectory(M.full_pack_dir(spec)) == 1 then
		return true
	end

	return false
end

---@param spec graft.Spec
---@return string
M.full_pack_dir = function(spec) return M.root_dir() .. "/" .. M.pack_dir(spec) end

---@param spec graft.Spec
---@return string
M.pack_dir = function(spec) return "pack/graft/" .. spec.type .. "/" .. spec.dir end

---@param spec graft.Spec
---@return string
M.git_url = function(spec) return "https://github.com/" .. spec.repo end

---@return string
M.root_dir = function()
	---@diagnostic disable-next-line: return-type-mismatch
	return vim.fn.stdpath("data") .. "/site/"
end

---@param spec graft.Spec
M.install = function(spec)
	show_status("Installing " .. spec.repo .. "...")

	local args = { "clone", "--depth", "1" }

	if spec.branch then
		args = vim.list_extend(args, { "-b", spec.branch })
	end

	args = vim.list_extend(args, { M.git_url(spec), M.full_pack_dir(spec) })

	graft.run("git", args, M.root_dir(), function(ok)
		if ok then
			show_status("Installing " .. spec.repo .. " [ok]")
			M.build(spec)
		else
			vim.notify("Failed to install " .. spec.repo, vim.log.levels.ERROR)
			show_status("Installing " .. spec.repo .. " [failed]")
		end
	end)
end

---@param spec graft.Spec
M.build = function(spec)
	if spec.build then
		if spec.build:match("^:") ~= nil then
			vim.notify(" * Building " .. spec.repo .. " with nvim command " .. spec.build)
			vim.cmd(spec.build)
		else
			vim.notify(" * Building " .. spec.repo .. " with system command " .. spec.build)
			local prev_dir = vim.fn.getcwd()
			vim.cmd("cd " .. M.full_pack_dir(spec))
			vim.fn.system(spec.build)
			vim.cmd("cd " .. prev_dir)
		end
	end
end

---@param spec graft.Spec
---@return boolean, string
M.uninstall = function(spec)
	local path = M.full_pack_dir(spec)

	-- validate the path
	if not path or path == "" then
		return false, "Invalid path"
	end

	-- Ensure we have an absolute normalized path
	path = vim.fn.fnamemodify(path, ":p")

	-- Sanity check to prevent accidental root or home directory deletion
	if path:match("^/+$") or path:match("^" .. vim.fn.expand("~") .. "/?$") then
		return false, "Preventing deletion of root or home directory"
	end

	-- First, try to remove the directory recursively
	local success, err = pcall(function()
		-- Use vim.fn.delete with 'rf' flag:
		-- 'r' means recursive
		-- 'f' means force (no error if file doesn't exist)
		local delete_result = vim.fn.delete(path, "rf")

		if delete_result ~= 0 then
			vim.notify("Failed to remove plugin " .. path .. ".", vim.log.levels.ERROR)
			error("Failed to delete directory")
		end
	end)

	show_status("Removing " .. spec.dir .. " [ok]")

	return success, ""
end

---@param dir string
---@return string|nil, string|nil
M.get_git_default_branch = function(dir)
	-- Path to the remote HEAD reference file
	local head_ref_path = dir .. "/.git/refs/remotes/origin/HEAD"

	-- Try to open the file
	local file = io.open(head_ref_path, "r")
	if not file then
		return nil, "Could not open " .. head_ref_path
	end

	-- Read the contents
	local content = file:read("*all")
	file:close()

	-- Extract the branch name using pattern matching
	local branch_name = string.match(content, "ref: refs/remotes/origin/([%w_-]+)")

	if branch_name then
		return branch_name, nil
	else
		return nil, "Could not extract branch name from " .. head_ref_path
	end
end

-- Update a plugin
---@param spec graft.Spec
---@return boolean
M.update_plugin = function(spec)
	local branch = spec.branch
	local error

	local cwd = M.full_pack_dir(spec)
	if not branch then
		branch, error = M.get_git_default_branch(cwd)
		if not branch then
			vim.print("Unable to get default branch for repo " .. spec.repo .. ": " .. error)
			return false
		end
	end

	if branch then
		graft.run("git", { "fetch", "--depth", "1", "--tags", "origin" }, cwd, function(tags_ok)
			if tags_ok then
				graft.run("git", { "fetch", "--depth", "1", "origin" }, cwd, function(branches_ok)
					if branches_ok then
						graft.run("git", { "checkout", branch }, cwd, function(checkout_ok)
							if checkout_ok then
								graft.run("git", { "pull", "--recurse-submodules", "--update-shallow" }, cwd, function(update_ok)
									if update_ok then
										vim.print("Update of " .. spec.repo .. " OK.")
									else
										vim.print(string.format("Graft: Unable to pull updates for %s", spec.repo))
									end
								end)
							else
								vim.print(string.format("Graft: Unable to checkout branch %s for %s", branch, spec.repo))
							end
						end)
					else
						vim.print(string.format("Graft: Unable to get branches for %s", spec.repo))
					end
				end)
			else
				vim.print(string.format("Graft: Unable to get tags for %s", spec.repo))
			end
		end)

		M.build(spec)
	end

	return true
end

-- Find all directories in pack/graft
---@param type string The type of pack to find (start or opt)
---@return table<string, table>
M.find_in_pack_dir = function(type)
	local pack_dir = M.root_dir() .. "/pack/graft/" .. type

	local plugins_by_dir = {}

	if vim.fn.isdirectory(pack_dir) == 1 then
		---@diagnostic disable-next-line: undefined-field
		local handle = vim.loop.fs_scandir(pack_dir)
		if handle then
			while true do
				---@diagnostic disable-next-line: undefined-field
				local name, ftype = vim.loop.fs_scandir_next(handle)
				if not name then
					break
				end
				if ftype == "directory" then
					plugins_by_dir[type .. ":" .. name] = { name = name, type = type }
				end
			end
		end
	end

	return plugins_by_dir
end

---@param plugins graft.Plugin
---@param opts? graft.Git.Sync
---@param on_complete? function Callback to run when all operations are complete
M.sync = function(plugins, opts, on_complete)
	---@type graft.Git.Sync
	local defaults = {
		install_plugins = true,
		update_plugins = false,
		remove_plugins = false,
	}

	opts = vim.tbl_deep_extend("force", defaults, opts or {})

	local desired = {}

	if opts.remove_plugins then
		for _, plugin in pairs(plugins) do
			if plugin.dir ~= "" then
				desired[plugin.type .. ":" .. plugin.dir] = true
			end
		end
	end

	if opts.remove_plugins then
		local installed_start = M.find_in_pack_dir("start")
		local installed_opt = M.find_in_pack_dir("opt")

		local installed = vim.tbl_extend("force", installed_start, installed_opt)

		-- Remove plugins that aren't in the plugin_list
		for installed_name, installed_data in pairs(installed) do
			if not desired[installed_name] then
				show_status("Removing " .. installed_data.name .. "..." .. " (" .. installed_data.type .. ")")
				M.uninstall({ dir = installed_data.name, type = installed_data.type })
			end
		end
	end

	-- Install missing plugins
	for _, spec in pairs(plugins) do
		if opts.install_plugins and not M.is_installed(spec) then
			show_status("Installing " .. spec.repo .. "...")
			M.install(spec)
		elseif opts.update_plugins then
			show_status("Updating " .. spec.repo .. "...")
			M.update_plugin(spec)
		end
	end

	-- Wait for all operations to complete if a callback was provided
	if on_complete then
		graft.wait_for_completion(function()
			show_status("Graft sync complete.")
			on_complete()
		end)
	end
end

---Setup graft-git
---@param opts? graft.Git.Sync Configuration options
M.setup = function(opts)
	graft.register_hook("post_register", function(plugins)
		-- Create a promise-like pattern with a callback
		local setup_complete = false

		-- Run sync with a completion callback
		M.sync(plugins, opts, function() setup_complete = true end)

		-- Block until setup is complete
		vim.wait(60000, function() return setup_complete end, 100)
	end)

	vim.api.nvim_create_user_command("GraftInstall", function()
		show_status("Installing plugins...")
		M.sync(
			graft.plugins,
			{ install_plugins = true, remove_plugins = false, update_plugins = false },
			function() vim.notify("Graft: Plugin installation complete", vim.log.levels.INFO) end
		)
	end, {})
	vim.api.nvim_create_user_command("GraftRemove", function()
		show_status("Removing plugins...")
		M.sync(
			graft.plugins,
			{ install_plugins = false, remove_plugins = true, update_plugins = false },
			function() vim.notify("Graft: Plugin removal complete", vim.log.levels.INFO) end
		)
	end, {})
	vim.api.nvim_create_user_command("GraftUpdate", function()
		show_status("Updating plugins...")
		M.sync(
			graft.plugins,
			{ install_plugins = false, remove_plugins = false, update_plugins = true },
			function() vim.notify("Graft: Plugin update complete", vim.log.levels.INFO) end
		)
	end, {})
	vim.api.nvim_create_user_command("GraftSync", function()
		show_status("Syncing plugins...")
		M.sync(
			graft.plugins,
			{ install_plugins = true, remove_plugins = true, update_plugins = true },
			function() vim.notify("Graft: Plugin sync complete", vim.log.levels.INFO) end
		)
	end, {})
end

return M
