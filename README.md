# codeactions-on-save.nvim

A Neovim plugin to register specific code actions to be run automatically on
file save, based on file patterns.

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "fnune/codeactions-on-save.nvim",
  config = function()
    local cos = require("codeactions-on-save")
    cos.register({ "*.py" }, { "source.organizeImports" })
    cos.register({ "*.ts", "*.tsx" }, { "source.organizeImports.biome", "source.fixAll" })
  end
}
```

The default timeout for code actions is 100ms. You can pass anything else if necessary, in `ms`:

```lua
cos.register({ "*.ts" }, { "source.organizeImports" }, 3000)
```

## Composing with an existing autocmd

If you already have a `BufWritePre` autocmd (for formatting, custom logic, etc.)
and want to run code actions inline rather than via a separate autocmd, call
`apply` directly:

```lua
vim.api.nvim_create_autocmd("BufWritePre", {
  pattern = { "*.ts" },
  callback = function(args)
    require("codeactions-on-save").apply(
      { "source.organizeImports", "source.fixAll" },
      args.buf,
      3000
    )
    -- ... other on-save work
  end,
})
```

`apply(kinds, buf, timeout_ms?)` is the same mechanism `register` uses
internally; the timeout defaults to 100ms.

## Inspecting code actions

To find out the action kind of the action you want to run, use this while
inside a buffer with an LSP client attached:

```
:lua require("codeactions-on-save").inspect()
```
