# Graft.nvim

![tests](https://github.com/tlj/graft.nvim/actions/workflows/tests.yml/badge.svg)
![typecheck](https://github.com/tlj/graft.nvim/actions/workflows/typecheck.yml/badge.svg)

A minimal Neovim plugin manager that handles lazy loading and configuration management using git submodules.

## Features

- Lazy loading via multiple triggers (commands, events, filetypes, keymaps)
- Git submodule-based installation
- Zero dependencies
- Simple configuration API
- Hooks to enable other plugins to extend the functionality of graft.nvim

## Extensions

graft.nvim supports extensions which enables new functionality.

## Installation

```bash
git clone --depth=1 https://github.com/tlj/graft.nvim \
    "${XDG_DATA_HOME:-$HOME/.local/share}"/nvim/site/pack/graft/start/graft.nvim
```

## Usage

Basic setup in your init.lua - see [tlj/dotfiles](https://github.com/tlj/dotfiles/blob/master/nvim/dot-config/nvim/init.lua) for inspiration.

`graft.nvim` will try to resolve and automatically require the right module by calling `setup(settings)` on that module. If you want
to overwrite this behaviour you can configure your own `setup` function.

```lua
local ok, graft = pcall(require, "graft")
if not ok then
  vim.notify("Graft is not installed")
  return
end

graft.setup({
  -- Plugins to load immediately
  start = {
    { "catppuccin/nvim", { dir = "catppuccin", setup = function() vim.cmd("colorscheme catppuccin-mocha") end } },
  },
  
  -- Plugins to load lazily
  opt = {
    -- Load on command
    { "nvim-telescope/telescope.nvim", { cmds = { "Telescope" }, requires = { "plenary.nvim" } } },
    
    -- Load on keymap
    { "stevearc/oil.nvim", { keys = { ["<leader>tt"] = { cmd = function() require("oil").open_float() end, desc = "Open Oil file browser" } } } },
    
    -- Load on filetype (blazingly fast)
    { "simrat39/rust-tools.nvim", { ft = { "rust" } } },
    
    -- Load on events
    { "nvim-lualine/lualine.nvim", { events = { "VimEnter" } } },

    -- Define the plugin in lua/config/plugins/stevearc--conform.lua
    -- The file should return the lua table instead of defining it inline here.
    -- Use this option when a plugin needs a lot of configuration, and you 
    -- want to keep your init file clean.
    graft.include("stevearc/conform.nvim"),
  }
})
```


## Plugin Specification Options

Each plugin can have the following specification options:

- `name`: Plugin name if different from repo name
- `dir`: Directory name if different from repo name
- `branch`: The branch or tag to follow (follows default branch if empty)
- `settings`: Table passed to plugin's setup() function
- `requires`: Dependencies to load before this plugin
- `cmds`: List of commands that trigger lazy loading
- `events`: List of events that trigger loading
- `pattern`: Pattern for event matching
- `after`: Load after specified plugins are loaded
- `ft`: Filetypes that trigger loading
- `keys`: Keymaps with commands and descriptions
- `setup`: Custom setup function
- `build`: Build command. If it starts with : it will be treated as a vim cmd, else a shell command.

## Adding/Removing Plugins

You can have `graft.nvim` automatically install/remove plugins.

```lua
require("graft.git").setup({ install_plugins = true, remove_plugins = true })

```

## Extensions interface

You can register a hook through the register_hook(hook, opts) command.

```lua
register_hook("pre_setup", function() print("pre_setup hook") end)
```

Available hooks:

- pre_setup(config) - Runs at the start of the setup() function
- post_setup(config) - Runs after the setup() function
- post_register(plugins) - Runs after all plugins have been registered
- pre_load(name) - Runs before a plugin is loaded
- post_load(name) - Runs after a plugin has been loaded

## Philosophy and Goals

### Graft Should

- [x] Configure and lazy load plugins through simple configuration
- [x] Expect plugins to be Neovim packages in site/pack/ folder
- [x] Use explicit configuration and loading
- [x] Support running plugins out of order while retaining full configuration

### Should Not

- [x] Implicitly load configuration
