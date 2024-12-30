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

graft.nvim supports extensions which enables new functionality. Available extensions:

- [graft-git.nvim](https://github.com/tlj/graft-git.nvim) Automatically install/remove/update git submodules
- [graft-ui.nvim](https://github.com/tlj/graft-ui.nvim) A simple UI to see the status of installed plugins

## Installation

Add the following snippet to your init.lua file. This will ensure that your dotfiles is a git repository
by running git init if it is not, then add `graft.nvim` as a submodule under `pack/graft/start`. The
`graft()` command takes a list of extensions to install. If you want `graft.nvim` to automatically pull
and remove plugins, you can add the `git` extension.

```lua
local function graft(e)
 local c=vim.fn.shellescape(vim.fn.stdpath('config'))
 if not vim.fn.system('git -C '..c..' rev-parse --is-inside-work-tree'):match('^true') then
   vim.fn.system('git -C '..c..' init')
   if vim.v.shell_error~=0 then vim.notify('Git init failed','ERROR') vim.cmd('qa!') end
 end
 e=e or {''}
 table.insert(e,'')
 for _,x in ipairs(e) do
   local n=x~='' and '-'..x or ''
   if not pcall(require,'graft'..n) then
     vim.fn.system(string.format('git -C %s submodule add -f https://github.com/tlj/graft%s.nvim.git pack/graft/start/graft%s.nvim',c,n,n))
     if vim.v.shell_error~=0 then vim.notify('Failed: graft'..n..'.nvim','ERROR') vim.cmd('qa!') end
     package.loaded['graft'..n]=nil
   end
 end
 vim.cmd'packloadall!'
end
graft{'git','ui'}
```

You can also manually install it as a one time operation:

```bash
:execute '!git -C ' .. stdpath('config') .. ' submodule add https://github.com/tlj/graft.nvim pack/graft/start/graft.nvim'
```

## Usage

Basic setup in your init.lua:

```lua
local ok, graft = pcall(require, "graft")
if not ok then
  vim.notify("Graft is not installed")
  return
end

graft.setup({
  -- Plugins to load immediately
  now = {
    { "catppuccin/nvim", { name = "catppuccin", setup = function() vim.cmd("colorscheme catppuccin-mocha") end } },
  },
  
  -- Plugins to load lazily
  later = {
    -- Load on command
    { "telescope.nvim", { cmds = { "Telescope" }, requires = { "plenary.nvim" } } },
    
    -- Load on keymap
    { "oil.nvim", { keys = { ["<leader>tt"] = { cmd = function() require("oil").open_float() end, desc = "Open Oil file browser" } } } },
    
    -- Load on filetype
    { "rust-tools.nvim", { ft = { "rust" } } },
    
    -- Load on events
    { "lualine.nvim", { events = { "VimEnter" } } },
  }
})
```

## Plugin Specification Options

Each plugin can have the following specification options:

- `name`: Plugin name if different from repo name
- `dir`: Directory name if different from repo name
- `settings`: Table passed to plugin's setup() function
- `requires`: Dependencies to load before this plugin
- `cmds`: List of commands that trigger lazy loading
- `events`: List of events that trigger loading
- `pattern`: Pattern for event matching
- `after`: Load after specified plugins are loaded
- `ft`: Filetypes that trigger loading
- `keys`: Keymaps with commands and descriptions
- `setup`: Custom setup function

## Adding/Removing Plugins

You can use the [graft-git.nvim](https://github.com/tlj/graft-git.nvim) extension to handle this automatically, or
you can handle this manually either through the terminal or through nvim commands.

Add plugins as git submodules:

```bash
:execute '!git -C ' .. stdpath('config') .. ' submodule add https://github.com/author/plugin pack/graft/start/plugin'
# or for opt plugins
:execute '!git -C ' .. stdpath('config') .. ' submodule add https://github.com/author/plugin pack/graft/opt/plugin'
```

Remove plugins:

```bash
:execute '!git -C ' .. stdpath('config') .. ' submodule deinit -f pack/graft/opt/plugin'
:execute '!git -C ' .. stdpath('config') .. ' rm -f pack/graft/opt/plugin'
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
- [x] Expect plugins to be Neovim packages in pack/ folder
- [x] Be added as a submodule itself
- [x] Use explicit configuration and loading
- [x] Support running plugins out of order while retaining full configuration

### Should Not

- [x] Change the filesystem (download/remove plugins)
- [x] Implicitly load configuration
