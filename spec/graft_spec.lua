local assert = require("luassert")
local stub = require("luassert.stub")
local spy = require("luassert.spy")

describe("Register plugin", function()
	local notify_spy
	local original_opt
	local cmd_stub
	local graft

	before_each(function()
		notify_spy = stub(vim, "notify")
		original_opt = vim.opt
		vim.opt = {
			rtp = {
				append = stub(),
			},
		}
		cmd_stub = stub(vim, "cmd")
		graft = require("graft")
		graft.plugins = {}
		graft.loaded = {}
	end)

	after_each(function()
		notify_spy:revert()
		cmd_stub:revert()
		vim.opt = original_opt
	end)

	it("Gets the correct plugin name", function()
		assert.are.same("dummy", graft.get_plugin_name("tlj/dummy.nvim"))
		assert.are.same("example", graft.get_plugin_name("tlj/example"))
		assert.are.same("statusline", graft.get_plugin_name("statusline"))
	end)

	it("Gets the correct dir name", function()
		assert.are.same("dummy.nvim", graft.get_plugin_dir("tlj/dummy.nvim"))
		assert.are.same("example", graft.get_plugin_dir("tlj/example"))
		assert.are.same("", graft.get_plugin_dir("statusline"))
	end)

	describe("Adds packadd or runtime path for dir", function()
		it("Does runtimepath when the path is a local dir", function()
			graft.load_plugin_path("~/src/dummy.nvim")
			assert.stub(vim.opt.rtp.append).was_called()
			assert.stub(cmd_stub).was_not_called()
		end)

		it("Does packadd when the path is a repo dir", function()
			graft.load_plugin_path("dummy.nvim")
			assert.stub(cmd_stub).was_called_with("packadd dummy.nvim")
			assert.stub(vim.opt.rtp.append).was_not_called()
		end)

		it("Does nothing when the path is empty", function()
			graft.load_plugin_path("")
			assert.stub(cmd_stub).was_not_called()
			assert.stub(vim.opt.rtp.append).was_not_called()
		end)
	end)

	it("Creates lazy commands", function()
		local create_cmd_stub = stub(vim.api, "nvim_create_user_command")

		graft.register("tlj/dummy.nvim", { repo = "tlj/dummy.nvim", cmds = { "DummyHello", "DummyBye" } })

		assert.stub(create_cmd_stub).was_called(2)
		create_cmd_stub:revert()
	end)

	it("Creates lazy events", function()
		local create_cmd_stub = stub(vim.api, "nvim_create_autocmd")

		graft.register("tlj/dummy.nvim", { repo = "tlj/dummy.nvim", events = { "TestPreEvent", "TestPostEvent" } })

		assert.stub(create_cmd_stub).was_called(1)
		create_cmd_stub:revert()
	end)

	it("Creates after events", function()
		local create_cmd_stub = stub(vim.api, "nvim_create_autocmd")

		graft.register(
			"tlj/dummy.nvim",
			{ repo = "tlj/dummy.nvim", after = { "tlj/first.nvim", "tlj/another_first.nvim" } }
		)

		assert.stub(create_cmd_stub).was_called(2)
		create_cmd_stub:revert()
	end)

	it("Creates ft events", function()
		local create_cmd_stub = stub(vim.api, "nvim_create_autocmd")

		graft.register("tlj/dummy.nvim", { repo = "tlj/dummy.nvim", ft = { "lua", "markdown" } })

		assert.stub(create_cmd_stub).was_called(1)
		create_cmd_stub:revert()
	end)

	it("Creats keymaps", function()
		local keymap_set = stub(vim.keymap, "set")

		graft.register("tlj/dummy.nvim", {
			keys = {
				["<leader>dd"] = { cmd = function() vim.notify("dummy") end },
				["<leader>pp"] = { cmd = function() vim.notify("dummy dummy") end },
			},
		})

		assert.stub(keymap_set).was_called(2)
		keymap_set:revert()
	end)

	it("Registers requirements", function()
		assert.are.same({}, graft.plugins)

		graft.setup({
			later = {
				{
					"tlj/dummy.nvim",
					{
						requires = {
							{ "tlj/lib.nvim" },
							{ "tlj/ui.nvim", { name = "uilib", requires = { { "tlj/cli.nvim" } } } },
						},
					},
				},
				{ "tlj/nothing.nvim", { name = "everything" } },
				{ "tlj/another.nvim", { requires = { "tlj/nothing.nvim", "tlj/noquote.nvim" } } },
			},
		})

		assert.are.same({
			["tlj/graft.nvim"] = {
				name = "graft",
				dir = "graft.nvim",
				repo = "tlj/graft.nvim",
				type = "now",
				setup = graft.setup_callback,
			},
			["tlj/dummy.nvim"] = {
				name = "dummy",
				dir = "dummy.nvim",
				repo = "tlj/dummy.nvim",
				type = "later",
				requires = {
					{ "tlj/lib.nvim" },
					{ "tlj/ui.nvim", { name = "uilib", requires = { { "tlj/cli.nvim" } } } },
				},
			},
			["tlj/lib.nvim"] = {
				dir = "lib.nvim",
				name = "lib",
				repo = "tlj/lib.nvim",
				type = "later",
			},
			["tlj/ui.nvim"] = {
				dir = "ui.nvim",
				name = "uilib",
				repo = "tlj/ui.nvim",
				type = "later",
				requires = { { "tlj/cli.nvim" } },
			},
			["tlj/cli.nvim"] = {
				dir = "cli.nvim",
				name = "cli",
				repo = "tlj/cli.nvim",
				type = "later",
			},
			["tlj/another.nvim"] = {
				name = "another",
				dir = "another.nvim",
				repo = "tlj/another.nvim",
				requires = { "tlj/nothing.nvim", "tlj/noquote.nvim" },
				type = "later",
			},
			["tlj/nothing.nvim"] = { name = "everything", dir = "nothing.nvim", repo = "tlj/nothing.nvim", type = "later" },
			["tlj/noquote.nvim"] = { name = "noquote", dir = "noquote.nvim", repo = "tlj/noquote.nvim", type = "later" },
		}, graft.plugins)
	end)

	it("Registers valid plugins", function()
		local load_spy = stub(graft, "load")

		assert.are.same({}, graft.plugins)

		graft.setup({
			now = {
				{ "tlj/dummy.nvim", { name = "dummy_plugin" } },
				{ "tlj/empty.nvim" },
				{ "tlj/example" },
				{ "statusline" },
				{ "custom-plugin", { dir = "~/src/custom-plugin.nvim" } },
			},
			later = {
				{ "tlj/graft-ext.nvim", { name = "graft_ext" } },
				{ "" },
			},
		})

		assert.are.same({
			-- Should retain the name set in setup and determine the correct dir name
			["tlj/dummy.nvim"] = { name = "dummy_plugin", dir = "dummy.nvim", repo = "tlj/dummy.nvim", type = "now" },
			-- Should determine both name and dir from repo name
			["tlj/empty.nvim"] = { name = "empty", dir = "empty.nvim", repo = "tlj/empty.nvim", type = "now" },
			-- Should determine both name and dir from repo name, without extension
			["tlj/example"] = { name = "example", dir = "example", repo = "tlj/example", type = "now" },
			-- plugins which are not github repos are most likely not in pack, so
			-- we don't set dir
			["statusline"] = { name = "statusline", dir = "", repo = "statusline", type = "now" },
			-- we should be able to load a plugin from a local directory outside of
			-- neovim config by adding it to runtimepath
			["custom-plugin"] = {
				name = "custom-plugin",
				dir = "~/src/custom-plugin.nvim",
				repo = "custom-plugin",
				type = "now",
			},
			-- plugins from [later] is also added to plugins list
			["tlj/graft-ext.nvim"] = {
				name = "graft_ext",
				dir = "graft-ext.nvim",
				repo = "tlj/graft-ext.nvim",
				type = "later",
			},
			-- we add graft.nvim so it can be displayed and controlled by extensions
			["tlj/graft.nvim"] = {
				name = "graft",
				dir = "graft.nvim",
				repo = "tlj/graft.nvim",
				type = "now",
				setup = graft.setup_callback,
			}
		}, graft.plugins)

		assert.spy(notify_spy).was_called(1)
		assert.spy(load_spy).was_called(6)

		load_spy:revert()
	end)
end)

describe("Using hooks", function()
	local graft
	local empty_hooks = { pre_setup = {}, post_setup = {}, post_register = {}, pre_load = {}, post_load = {} }
	local callback = function() vim.print("Callback called") end

	before_each(function()
		graft = require("graft")
		graft.loaded = {}
		graft.plugins = {}
		graft.hooks = { pre_setup = {}, post_setup = {}, post_register = {}, pre_load = {}, post_load = {} }
	end)

	after_each(function()
		graft.loaded = {}
		graft.plugins = {}
		graft.hooks = { pre_setup = {}, post_setup = {}, post_register = {}, pre_load = {}, post_load = {} }
	end)

	it("has empty hooks by default", function() assert.are.same(empty_hooks, graft.hooks) end)

	it("returns false when registering invalid hook", function()
		local result = graft.register_hook("cook_it", callback)

		assert.is_false(result)
		assert.are.same(empty_hooks, graft.hooks)
	end)

	describe("registers hook", function()
		for k, _ in pairs(empty_hooks) do
			it(k, function()
				local result = graft.register_hook(k, callback)
				assert.is_true(result)
				assert.is.same(graft.hooks[k], { callback })
			end)
		end

		it("calls setup hooks", function()
			local hooks = {
				pre_setup = function(plugins) end,
				post_setup = function(plugins) end,
				post_register = function(plugins) end,
			}

			spy.on(hooks, "post_register")
			spy.on(hooks, "pre_setup")
			spy.on(hooks, "post_setup")

			graft.register_hook("post_register", hooks.post_register)
			graft.register_hook("pre_setup", hooks.pre_setup)
			graft.register_hook("post_setup", hooks.post_setup)

			local config = { later = { { "tlj/graft.nvim" } } }
			graft.setup(config)

			assert.spy(hooks.post_register).was_called_with({
				["tlj/graft.nvim"] = {
					dir = "graft.nvim",
					name = "graft",
					repo = "tlj/graft.nvim",
					type = "later",
				},
			})

			assert.spy(hooks.pre_setup).was_called_with(config)
			assert.spy(hooks.post_setup).was_called_with(config)
		end)

		it("calls load hooks", function()
			local hooks = {
				pre_load = function(repo) end,
				post_load = function(repo) end,
			}

			spy.on(hooks, "pre_load")
			spy.on(hooks, "post_load")

			graft.register_hook("pre_load", hooks.pre_load)
			graft.register_hook("post_load", hooks.post_load)

			local config = { later = { { "fake" } } }
			graft.setup(config)

			graft.load("fake")

			assert.spy(hooks.pre_load).was_called_with("fake")
			assert.spy(hooks.post_load).was_called_with("fake")
		end)
	end)
end)
