---@class graft.Graft
local M = {
	logfile = vim.fn.stdpath("log") .. "/graft.log",
	pending_operations = 0,
	on_all_complete_callback = nil,
}

---@type table<string, function[]>
M.hooks = {
	pre_setup = {},
	post_setup = {},
	post_register = {},
	pre_load = {},
	post_load = {},
	post_sync = {},
}

---Register a callback for a specific hook
---@param hook string The hook name
---@param callback function The callback function
---@return boolean
M.register_hook = function(hook, callback)
	if not M.hooks[hook] then
		return false
	end

	table.insert(M.hooks[hook], callback)
	return true
end

---Run all callbacks for a specific hook
---@param hook string The hook name
---@param ... any Arguments to pass to callbacks
M.run_hooks = function(hook, ...)
	for _, callback in ipairs(M.hooks[hook] or {}) do
		callback(...)
	end
end

---@class graft.Spec
---@field repo? string The repo for the plugin - automatically set from the defined repo in the setup
---@field type? string The type of plugin ("start" or "opt")
---@field name? string This is the name of the plugin if the module name is different from the url name
---@field dir? string This is the directory name of the plugin
---@field branch? string The branch to follow
---@field settings? table The settings for this plugin, will be sent to setup() function
---@field requires? (string | graft.Plugin)[] A list of repos which has to be loaded before this one
---@field cmds? string[] A list of commands which will load the plugin
---@field events? string[] A list of events which will load the plugin
---@field pattern? string Pattern for lazy loading auto commands (events, ft)
---@field after? string[] Load this plugin automatically after another plugin has been loaded
---@field ft? string[] Filetypes which will trigger loading of this plugin
---@field keys? table<string, {cmd:string|function, desc: string}> Keymaps with commands (string or function) and description
---@field setup? function Custom setup function. If not set, will try to find setup() automatically.
---@field build? string A command (vim cmd if it starts with :, system otherwise) to run after install

---@class graft.Plugin
---@field [1] string The github repo url of the plugin
---@field spec? graft.Spec The spec of the plugin (settings, etc)

---@class graft.Setup
---@field start? graft.Plugin[] Plugins to load immediately
---@field opt? graft.Plugin[] Plugins to load later

---@type table<string, graft.Spec>
M.plugins = {}

---@type table<string, boolean>
M.loaded = {}

-- Create an autogroup for our commands
M.autogroup = vim.api.nvim_create_augroup("graft_autogroup", { clear = true })

-- Try to determine the plugin name from repo name
---@param repo string The github repo url
---@return string
M.get_plugin_name = function(repo)
	local name = repo:match(".*/(.*)") or repo
	return name:gsub("%.[^%.]*$", "")
end

-- Try to determine the plugin direcgory from repo name
---@param repo string The github repo url
---@return string
M.get_plugin_dir = function(repo)
	local dir = repo:match(".*/(.*)")
	return dir or ""
end

-- Use libuv to spawn processes
-- Attribution for this function goes to paq-nvim
-- https://github.com/fsouza/paq-nvim/blob/main/lua/paq.lua
---@param process string
---@param args table
---@param cwd string
---@param cb function
M.run = function(process, args, cwd, cb)
	-- Increment pending operations counter
	M.pending_operations = M.pending_operations + 1

	local log = vim.uv.fs_open(M.logfile, "a+", 0x1A4)
	local stderr = vim.uv.new_pipe(false)
	if log and stderr then
		stderr:open(log)
	end
	local handle, pid
	handle, pid = vim.uv.spawn(
		process,
		{ args = args, cwd = cwd, stdio = { nil, nil, stderr }, env = {} },
		vim.schedule_wrap(function(code)
			if log then
				vim.uv.fs_close(log)
			end
			if stderr then
				stderr:close()
			end
			if handle then
				handle:close()
			end

			-- Call the original callback
			cb(code == 0)

			-- Decrement pending operations counter
			M.pending_operations = M.pending_operations - 1

			-- Check if all operations are complete
			if M.pending_operations == 0 and M.on_all_complete_callback then
				local callback = M.on_all_complete_callback
				M.on_all_complete_callback = nil
				if callback then
					callback()
				end
			end
		end)
	)
	if not handle then
		vim.notify(string.format("Graft: Failed to spawn %s (%s)", process, pid))
		-- Decrement counter if spawn failed
		M.pending_operations = M.pending_operations - 1

		-- Check if all operations are complete
		if M.pending_operations == 0 and M.on_all_complete_callback then
			local callback = M.on_all_complete_callback
			M.on_all_complete_callback = nil
			if callback then
				callback()
			end
		end
	end
end

-- Wait for all pending operations to complete
---@param callback function Function to call when all operations are complete
M.wait_for_completion = function(callback)
	if M.pending_operations == 0 then
		-- If no operations are pending, call the callback immediately
		callback()
	else
		-- Otherwise, store the callback to be called when operations complete
		M.on_all_complete_callback = callback
	end
end

---@param repo string
---@param spec? graft.Spec
M.register = function(repo, spec)
	if repo == "" then
		vim.notify("Can't register a plugin with empty name.")
		return
	end

	-- Set some defaults in the spec unless they are explicitly set already
	spec = vim.deepcopy(spec or {})
	spec.repo = repo
	spec.name = spec.name or M.get_plugin_name(repo)
	spec.dir = spec.dir or M.get_plugin_dir(repo)
	spec.type = spec.type or "opt"

	-- Register the plugin in our lookup table
	M.plugins[repo] = spec

	-- Register plugin requirements
	M.register_requirements(spec)

	-- Register lazy loading commands
	M.register_cmds(spec)

	-- Register lazy loading events
	M.register_events(spec)

	-- Register plugins which will trigger the loading of this plugin
	M.register_after(spec)

	-- Register filetypes which will trigger the plugin
	M.register_ft(spec)

	-- Register keys which will load plugin and trigger action
	M.register_keys(spec)
end

M.find_require_path_with_init = function(plugin_path)
	-- If no direct files found, check for directories with init.lua
	local init_files = vim.api.nvim_get_runtime_file("lua/*/init.lua", true)

	local plugin_init_files = vim.tbl_filter(function(file) return file:match(plugin_path) end, init_files)

	return plugin_init_files
end

---@return string[]
M.find_require_path_potential_modules = function(plugin_path)
	-- First check for any lua files directly in lua/
	local lua_files = vim.api.nvim_get_runtime_file(
		"lua/*.lua",
		true -- Get all matches
	)

	-- Filter and collect all potential module names
	local potential_modules = {}
	for _, file in ipairs(lua_files) do
		if file:match(plugin_path) then
			local mod_path = file:match("lua/([^/]+).lua$")
			if mod_path then
				table.insert(potential_modules, mod_path)
			end
		end
	end

	-- Sort modules by priority:
	-- 1. Exact match with plugin name (without nvim- prefix)
	-- 2. Shorter names (less likely to be auxiliary modules)
	-- 3. Alphabetical as fallback
	table.sort(potential_modules, function(a, b)
		local plugin_name = plugin_path:match("[^/]+$"):gsub("^nvim%-", "")
		local a_exact = a == plugin_name
		local b_exact = b == plugin_name

		if a_exact and not b_exact then
			return true
		end
		if b_exact and not a_exact then
			return false
		end

		if #a ~= #b then
			return #a < #b
		end
		return a < b
	end)

	return potential_modules
end

M.find_require_path = function(plugin_path)
	if plugin_path == "" then
		return nil
	end

	local escaped_path = plugin_path:gsub("%-", "%%-")

	local potential_modules = M.find_require_path_potential_modules(escaped_path)

	-- Try requiring modules in priority order
	for _, mod_path in ipairs(potential_modules) do
		local success = pcall(require, mod_path)
		if success then
			return mod_path
		end
		package.loaded[mod_path] = nil
	end

	local plugin_init_files = M.find_require_path_with_init(escaped_path)

	for _, file in ipairs(plugin_init_files) do
		-- Get the directory name that contains init.lua
		local mod_path = file:match("lua/([^/]+)/init.lua$")
		if mod_path then
			package.loaded[mod_path] = nil
			local success = pcall(require, mod_path)
			if success then
				return mod_path
			end
			package.loaded[mod_path] = nil
		end
	end

	return nil
end

-- Register the plugin requirements recursively
---@param spec graft.Spec
M.register_requirements = function(spec)
	-- If we require a plugin but it is not registered (yet), let's register it.
	-- Since the requires entries are of type graft.Plugin, they can set the
	-- plugin spec when they are defined as requirement.
	for _, req in ipairs(spec.requires or {}) do
		local name = ""
		local opts = {}
		if type(req) == "string" then
			name = req
		end
		if type(req) == "table" then
			name = req[1] or ""
			opts = req[2] or {}
		end
		if name ~= "" and M.plugins[name] == nil then
			M.register(name, opts)
		end
	end
end

-- Register a proxy user command which will load the plugin and then
-- trigger the command on the plugin
---@param spec graft.Spec
M.register_cmds = function(spec)
	for _, cmd in ipairs(spec.cmds or {}) do
		-- Register a command for each given commands
		vim.api.nvim_create_user_command(cmd, function(args)
			-- When triggered, delete this command
			vim.api.nvim_del_user_command(cmd)

			-- Then load the plugin
			M.load(spec.repo)

			-- Then trigger the original command
			vim.cmd(string.format("%s %s", cmd, args.args))
		end, {
			nargs = "*",
		})
	end
end

-- Register events which will trigger loading of the plugin
---@param spec graft.Spec
M.register_events = function(spec)
	if spec.events then
		vim.api.nvim_create_autocmd(spec.events, {
			group = M.autogroup,
			pattern = spec.pattern or "*",
			callback = function() M.load(spec.repo) end,
			once = true, -- we only need this to happen once
		})
	end
end

-- Register plugins which this plugin will load after, through listening
-- to user events emitted by plugins being loaded
---@param spec graft.Spec
M.register_after = function(spec)
	for _, after in ipairs(spec.after or {}) do
		vim.api.nvim_create_autocmd("User", {
			group = M.autogroup,
			pattern = after,
			callback = function() M.load(spec.repo) end,
			once = true, -- we only need this to happen once
		})
	end
end

-- Register filetypes which will trigger loading the plugin
---@param spec graft.Spec
M.register_ft = function(spec)
	if spec.ft then
		vim.api.nvim_create_autocmd("FileType", {
			group = M.autogroup,
			pattern = spec.ft,
			callback = function() M.load(spec.repo) end,
			once = true, -- we only need this to happen once
		})
	end
end

-- Register keys which will load the plugin and trigger an action
---@param spec graft.Spec
M.register_keys = function(spec)
	if not spec.keys then
		return
	end

	for key, _ in pairs(spec.keys) do
		local callback = function()
			vim.keymap.del("n", key)
			M.load(spec.repo)
			local keys = vim.api.nvim_replace_termcodes(key, true, true, true)
			vim.api.nvim_feedkeys(keys, "m", false)
		end

		vim.keymap.set("n", key, callback, {})
	end
end

-- This is a function which is called by the graft initialized setup,
-- which is basically a setup with the setup, so we want this to be
-- empty, but need it for testing to compare setup functions.
---@param config graft.Setup
M.setup_callback = function(config) end

-- Set up all the plugins and load the start-plugins
---@param config graft.Setup
M.setup = function(config)
	-- Run pre-setup hooks
	M.run_hooks("pre_setup", config)

	-- Validate the config
	-- require("graft.validate").validate_setup(config)

	-- Register and control ourselves
	if not M.plugins["tlj/graft.nvim"] then
		M.register("tlj/graft.nvim", { type = "start", setup = M.setup_callback })
	end

	-- Register all plugins before we load any, in case there is config set for a required
	-- plugin which is defined later
	for _, plugin in ipairs(config.start or {}) do
		local opts = plugin[2] or {}
		opts.type = "start"
		M.register(plugin[1] or "", opts)
	end

	for _, plugin in ipairs(config.opt or {}) do
		M.register(plugin[1] or "", plugin[2] or {})
	end

	M.run_hooks("post_register", M.plugins)

	-- Load start-plugins immediately
	for repo, spec in pairs(M.plugins or {}) do
		if spec.type == "start" then
			M.load(repo)
		end
	end

	-- Run post-setup hooks
	M.run_hooks("post_setup", config)
end

-- Add the plugin path to either runtimepath or packadd
---@param dir string The plugin directory
M.load_plugin_path = function(dir)
	-- No dir - no fun
	if dir == "" then
		return
	end

	-- If the string has a slash in it, it is most likely a reference
	-- to an actual path, so let's add that to the runtime
	if dir:match("/") ~= nil then
		vim.opt.rtp:append(dir)
		return
	end

	pcall(function() vim.cmd("packadd " .. dir) end)
	-- vim.cmd("packloadall!")
end

-- Load the required plugins
M.load_required = function(repo)
	for _, plugin in ipairs(repo.requires or {}) do
		local name
		if type(plugin) == "string" then
			name = plugin
		end
		if type(plugin) == "table" then
			name = plugin[1]
		end
		M.load(name or "")
	end
end

-- Load the plugin
---@param repo string Load the plugin finally
M.load = function(repo)
	if repo == "" then
		return
	end

	-- Run pre-load hooks
	M.run_hooks("pre_load", repo)

	-- Don't load the same plugin twice
	if M.loaded[repo] then
		return
	end
	M.loaded[repo] = true

	local spec = M.plugins[repo]
	if not spec then
		error("Tried to load unregistered plugin: " .. repo)
	end

	-- Load required plugins first
	M.load_required(spec)

	-- If a directory is set, we try to packadd it
	M.load_plugin_path(spec.dir)

	-- Require plugin, fall back to require_path if we are unable to
	-- require on plugin name. Worst case a custom setup()
	-- is needed to require the correct path.
	local ok, p = pcall(require, spec.name)
	if not ok then
		package.loaded[spec.name] = nil
		local require_path = M.find_require_path(spec.dir)
		if require_path then
			-- vim.print("Loading " .. spec.name .. " failed, trying " .. vim.inspect(require_path))
			ok, p = pcall(require, require_path)
			if not ok then
				-- vim.print(" .. that also failed.")
				package.loaded[require_path] = nil
			end
		else
			-- vim.print("Unable to load " .. spec.name .. ", found no fallback require path.")
		end
	end

	-- Try to find the correct setup function to call
	if p ~= nil and spec.setup and type(spec.setup) == "function" then
		spec.setup(spec.settings)
	elseif p ~= nil and p.setup and type(p.setup) == "function" then
		p.setup(spec.settings)
	end

	-- Setup keymaps from config
	for key, opts in pairs(spec.keys or {}) do
		vim.keymap.set("n", key, opts.cmd, { desc = opts.desc or "", noremap = false, silent = true })
	end

	-- Trigger an event saying plugin is loaded, so other plugins
	-- which are waiting for us can trigger.
	vim.api.nvim_exec_autocmds("User", { pattern = repo })

	-- Run post-load hooks
	M.run_hooks("post_load", repo)
end

---@param name string
---@return string
local function normalize_require_name(name)
	-- Change / to -- and lowercase the name of the repo
	name = name:gsub("/", "%-%-"):lower()
	-- First remove .lua or .nvim extension if present
	name = name:gsub("%.lua$", ""):gsub("%.nvim$", "")
	-- Then replace remaining dots with dashes
	name = name:gsub("%.", "-")
	return name
end

-- Include a spec file with a plugin definition
---@param repo string
M.include = function(repo)
	-- remove extension and add the load path
	local fp = "config/plugins/" .. normalize_require_name(repo)

	-- try to load it
	local hasspec, spec = pcall(require, fp)
	if not hasspec then
		vim.notify("Could not include " .. fp .. ".lua", vim.log.levels.ERROR)
		return
	end

	return spec
end

return M
