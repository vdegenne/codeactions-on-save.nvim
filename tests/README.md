# Tests

Each spec boots a subprocess LSP, attaches it to a buffer, triggers `BufWritePre`, and asserts the resulting buffer.

## Running

```
make test
```

First run clones plenary into `.tests/` (gitignored).

## Layout

```
spec/                 busted specs (scenarios inline)
fake_lsp/server.lua   stdio transport for the LSP
helpers.lua           spec setup glue
minimal_init.lua
```

## Two processes

`make test` runs the specs in one Neovim. Each spec spawns a child Neovim that acts as the LSP:

```
nvim --headless -l tests/fake_lsp/server.lua <scenario>
```

The scenario is a factory function passed to `h.fake_lsp`. The helper dumps its bytecode (`string.dump`) to a temp file and passes the path; the child `dofile`s it. That's how the scenario crosses the process boundary while still being written inline.

The factory must not capture upvalues from outside itself: `string.dump` drops upvalue values. The helper enforces this with `debug.getupvalue` and errors loudly if you try. Anything you need, define inside the factory.

## Anatomy of a test

```lua
it("does the thing", function()
  h.user_setup({
    { pattern = { "*.fake" }, kinds = { "source.foo" }, timeout_ms = 5000 },
  })
  h.buffer({ "line 1", "line 2", "line 3" })
  h.fake_lsp(function()
    return {
      handlers = {
        ["textDocument/codeAction"] = function(params)
          return { ... }
        end,
      },
    }
  end)

  vim.cmd("silent write")
  assert.are.same({ ... }, h.lines())
end)
```

- `h.user_setup(configs)` is the simulated `init.lua`. Each entry calls `plugin.register(pattern, kinds, timeout_ms)`.
- `h.buffer(lines)` opens `repro.fake` in a tmpdir with the given starting contents.
- `h.fake_lsp(fn)` dumps and spawns the scenario, waits for `initialized`, attaches it to the current buffer.
- `server.lua` ships defaults for `initialize`, `shutdown`, and document tracking (`didOpen` / `didChange` / `didClose` keep `state.docs`, a `uri -> text` map, fresh). A scenario overrides whatever else the test cares about.
- `h.cleanup` (via `after_each`) tears it all down.
