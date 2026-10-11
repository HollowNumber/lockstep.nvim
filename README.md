# lockstep.nvim 


Keep C declarations and definitions in lockstep.

> [!WARNING]
> Currently in early development, the sync works but expect changes.


## Features

- Signature sync: edit a function's parameters in the `.c` file or the header, and the other side is updated to match. 
- Code action: offers the sync in your code-actions menu when the cursor is on a signature (opt-in, see [Configuration])

## Planned features 

- Live split view: see the counterpart update in a split as you type.
- Scaffolding: generate a header from a source file (or stubs from a header), and add missing declarations as you go. 

## Installation

With `vim.pack` (Neovim 0.12+):

```lua
vim.pack.add({ "https://github.com/HollowNumber/lockstep.nvim" })
```

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{ "HollowNumber/lockstep.nvim", opts = {} }
```

No `setup()` call is required.

## Usage

Put the cursor on a function's definition or declaration and run:

```vim
:Lockstep sync
```

The other side is rewritten to match and left unsaved, so you can review it.
To map it to a key:

```lua
vim.keymap.set("n", "<leader>cs", "<Plug>(lockstep-sync)")
```

lockstep asks clangd where the other side lives, and falls back to Treesitter
and searching the project's files, so it also works without clangd.

## Configuration

Set `vim.g.lockstep` anywhere in your config. These are the defaults:

```lua
vim.g.lockstep = {
	-- Offer the sync in the code-action menu (starts a small in-process LSP client)
	code_action = false,
	-- How long to wait for clangd before trying the next way of finding the other side
	lsp_timeout_ms = 1000,
	-- Search the project's files when nothing else finds the other side
	project_scan = true,
}
```

Or, equivalently, with lazy.nvim's `opts` or `require("lockstep").setup({ ... })`.

Invalid options fall back to their defaults with a warning.
Run `:checkhealth lockstep` to check your setup.

## Requirements 

- Neovim 0.11+ 
- The Treesitter C parser 
- [clangd](https://clangd.llvm.org/) (optional, but recommended for locating declarations across files)


## Development

### Run tests


Running tests requires either

- [luarocks][luarocks]
- or [busted][busted] and [nlua][nlua]

to be installed[^1].

[^1]: The test suite assumes that `nlua` has been installed
      using luarocks into `~/.luarocks/bin/`.

You can then run:

```bash
luarocks test --local
# or
busted
```

Or if you want to run a single test file:

```bash
luarocks test spec/path_to_file.lua --local
# or
busted spec/path_to_file.lua
```

If you see an error like `module 'busted.runner' not found`:

```shell
eval $(luarocks path --no-bin)
```

For this to work you need to have Lua 5.1 set as your default version for
luarocks. If that's not the case you can pass `--lua-version 5.1` to all the
luarocks commands above.

[luarocks]: https://luarocks.org
[busted]: https://lunarmodules.github.io/busted/
[nlua]: https://github.com/mfussenegger/nlua



