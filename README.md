# lockstep.nvim 


Keep C declarations and definitions in lockstep.

> [!WARNING]
> Currently in early development, the sync works but expect changes.


## Features

- Signature sync: edit a function's parameters in the `.c` file or the header, and the other side is updated to match. 
## Planned features 

- Live split view: see the counterpart update in a split as you type.
- Scaffolding: generate a header from a source file (or stubs from a header), and add missing declarations as you go. 

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



