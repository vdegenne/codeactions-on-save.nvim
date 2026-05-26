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

  it("preserves buffer content when multiple kinds yield interacting edits (issue #7)", function()
    h.user_setup({
      { pattern = { "*.fake" }, kinds = { "source.addMissingImports", "source.organizeImports" }, timeout_ms = 5000 },
    })
    h.buffer([[
      line 1
      line 2
      line 3
    ]])
    h.fake_lsp(function()
      return {
        handlers = {
          ["textDocument/codeAction"] = function(params, state)
            local uri = params.textDocument.uri
            local text = state.docs[uri] or ""

            local row, row_of_line_2 = 0, nil
            for line in (text .. "\n"):gmatch("([^\n]*)\n") do
              if line == "line 2" then
                row_of_line_2 = row
                break
              end
              row = row + 1
            end

            local only = {}
            for _, k in ipairs(params.context.only or {}) do
              only[k] = true
            end

            local actions = {}
            if only["source.addMissingImports"] then
              table.insert(actions, {
                title = "Insert ADDED at top",
                kind = "source.addMissingImports",
                edit = { changes = { [uri] = { {
                  range = {
                    start = { line = 0, character = 0 },
                    ["end"] = { line = 0, character = 0 },
                  },
                  newText = "ADDED\n",
                } } } },
              })
            end
            if only["source.organizeImports"] and row_of_line_2 then
              table.insert(actions, {
                title = "Replace line 2 with MODIFIED",
                kind = "source.organizeImports",
                edit = { changes = { [uri] = { {
                  range = {
                    start = { line = row_of_line_2, character = 0 },
                    ["end"] = { line = row_of_line_2 + 1, character = 0 },
                  },
                  newText = "MODIFIED\n",
                } } } },
              })
            end
            return actions
          end,
        },
      }
    end)

    vim.cmd("silent write")

    assert.are.same(h.text([[
      ADDED
      line 1
      MODIFIED
      line 3
    ]]), h.lines())
  end)

  it("apply() applies code actions to the given buffer", function()
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
                newText = "DIRECT\n",
              } } } },
            } }
          end,
        },
      }
    end)

    require("codeactions-on-save").apply({ "source.organizeImports" }, vim.api.nvim_get_current_buf(), 5000)

    assert.are.same(h.text([[
      DIRECT
      line 2
      line 3
    ]]), h.lines())
  end)

  it("command-style actions mutate the buffer via reverse workspace/applyEdit", function()
    h.buffer([[
      line 1
      line 2
    ]])
    h.fake_lsp(function()
      return {
        handlers = {
          ["textDocument/codeAction"] = function(params)
            return { {
              title = "Run command",
              kind = "source.fixAll",
              command = {
                title = "Run command",
                command = "myCommand",
                arguments = { params.textDocument.uri },
              },
            } }
          end,
          ["workspace/executeCommand"] = function(params, state)
            local uri = params.arguments[1]
            state.send_request("workspace/applyEdit", {
              edit = { changes = { [uri] = { {
                range = {
                  start = { line = 0, character = 0 },
                  ["end"] = { line = 1, character = 0 },
                },
                newText = "COMMANDED\n",
              } } } },
            })
            return { applied = true }
          end,
        },
      }
    end)

    require("codeactions-on-save").apply({ "source.fixAll" }, vim.api.nvim_get_current_buf(), 5000)

    assert.are.same(h.text([[
      COMMANDED
      line 2
    ]]), h.lines())
  end)

  it("warns and stops recursing after 3 resolve attempts when actions never resolve", function()
    local notifications = {}
    h.stub(vim, "notify", function(msg, level)
      table.insert(notifications, { msg = msg, level = level })
    end)

    h.user_setup({
      { pattern = { "*.fake" }, kinds = { "source.organizeImports" }, timeout_ms = 5000 },
    })
    h.buffer([[
      line 1
      line 2
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
          ["textDocument/codeAction"] = function()
            return { {
              title = "Stuck",
              kind = "source.organizeImports",
              data = { stuck = true },
            } }
          end,
          ["codeAction/resolve"] = function(action)
            return action
          end,
        },
      }
    end)

    vim.cmd("silent write")

    assert.are.same(h.text([[
      line 1
      line 2
    ]]), h.lines())

    local warnings = {}
    for _, n in ipairs(notifications) do
      if n.level == vim.log.levels.WARN and n.msg:match("Max resolve attempts reached") then
        table.insert(warnings, n.msg)
      end
    end
    assert.are.equal(1, #warnings)
    assert.matches("source%.organizeImports", warnings[1])
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
