local h = require("helpers")

describe("codeactions-on-save", function()
  after_each(h.cleanup)

  it("applies an inline edit from a single action", function()
    h.user_setup({
      { pattern = { "*.fake" }, kinds = { "source.organizeImports" }, timeout_ms = 5000 },
    })
    h.buffer([[
      line 1
      line 2
      line 3
    ]])
    h.fake_lsp(function()
      return {
        handlers = {
          ["textDocument/codeAction"] = function(params)
            return { {
              title = "Replace line 1",
              kind = "source.organizeImports",
              edit = { changes = { [params.textDocument.uri] = { {
                range = {
                  start = { line = 0, character = 0 },
                  ["end"] = { line = 1, character = 0 },
                },
                newText = "REPLACED\n",
              } } } },
            } }
          end,
        },
      }
    end)

    vim.cmd("silent write")

    assert.are.same(h.text([[
      REPLACED
      line 2
      line 3
    ]]), h.lines())
  end)

  it("does not apply edits when the file does not match any registered pattern", function()
    h.user_setup({
      { pattern = { "*.never-matches" }, kinds = { "source.organizeImports" }, timeout_ms = 5000 },
    })
    h.buffer([[
      line 1
      line 2
      line 3
    ]])
    h.fake_lsp(function()
      return { handlers = {} }
    end)

    vim.cmd("silent write")

    assert.are.same(h.text([[
      line 1
      line 2
      line 3
    ]]), h.lines())
  end)

  it("applies actions that require codeAction/resolve", function()
    h.user_setup({
      { pattern = { "*.fake" }, kinds = { "source.organizeImports" }, timeout_ms = 5000 },
    })
    h.buffer([[
      line 1
      line 2
      line 3
    ]])
    h.fake_lsp(function()
      return {
        handlers = {
          initialize = function()
            return {
              capabilities = {
                textDocumentSync = 1,
                codeActionProvider = { resolveProvider = true },
              },
              serverInfo = { name = "fake-lsp" },
            }
          end,
          ["textDocument/codeAction"] = function(params)
            return { {
              title = "Organize",
              kind = "source.organizeImports",
              data = { uri = params.textDocument.uri },
            } }
          end,
          ["codeAction/resolve"] = function(action)
            action.edit = { changes = { [action.data.uri] = { {
              range = {
                start = { line = 0, character = 0 },
                ["end"] = { line = 1, character = 0 },
              },
              newText = "RESOLVED\n",
            } } } }
            return action
          end,
        },
      }
    end)

    vim.cmd("silent write")

    assert.are.same(h.text([[
      RESOLVED
      line 2
      line 3
    ]]), h.lines())
  end)
end)
