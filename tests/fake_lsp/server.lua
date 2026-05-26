local uv = vim.uv or vim.loop

local scenario_path = arg and arg[1]
if not scenario_path then
  io.stderr:write("fake-lsp: scenario path required as arg[1]\n")
  os.exit(1)
end

local stdin = uv.new_pipe(false)
local stdout = uv.new_pipe(false)
stdin:open(0)
stdout:open(1)

local state = { docs = {} }

local handlers = {
  initialize = function()
    return {
      capabilities = {
        textDocumentSync = 1,
        codeActionProvider = { resolveProvider = false },
      },
      serverInfo = { name = "fake-lsp" },
    }
  end,
  shutdown = function() return vim.NIL end,
}

local notifications = {
  initialized = function() end,
  exit = function() os.exit(0) end,
  ["textDocument/didOpen"] = function(params)
    state.docs[params.textDocument.uri] = params.textDocument.text
  end,
  ["textDocument/didChange"] = function(params)
    local last = params.contentChanges[#params.contentChanges]
    state.docs[params.textDocument.uri] = last.text
  end,
  ["textDocument/didClose"] = function(params)
    state.docs[params.textDocument.uri] = nil
  end,
}

local scenario = dofile(scenario_path)
for method, fn in pairs(scenario.handlers or {}) do handlers[method] = fn end
for method, fn in pairs(scenario.notifications or {}) do notifications[method] = fn end

local function send(msg)
  local body = vim.json.encode(msg)
  stdout:write("Content-Length: " .. #body .. "\r\n\r\n" .. body)
end

local function dispatch(msg)
  if msg.id ~= nil and msg.method then
    local handler = handlers[msg.method]
    if handler then
      local ok, result = pcall(handler, msg.params, state)
      if ok then
        send({ jsonrpc = "2.0", id = msg.id, result = result })
      else
        send({ jsonrpc = "2.0", id = msg.id, error = { code = -32603, message = tostring(result) } })
      end
    else
      send({ jsonrpc = "2.0", id = msg.id, error = { code = -32601, message = "Method not found: " .. msg.method } })
    end
  elseif msg.method then
    local handler = notifications[msg.method]
    if handler then pcall(handler, msg.params, state) end
  end
end

local buffer = ""

local function try_consume()
  while true do
    local header_end = buffer:find("\r\n\r\n", 1, true)
    if not header_end then return end
    local length = tonumber(buffer:sub(1, header_end - 1):match("Content%-Length:%s*(%d+)"))
    if not length then
      buffer = buffer:sub(header_end + 4)
      return
    end
    local body_start = header_end + 4
    if #buffer < body_start + length - 1 then return end
    local body = buffer:sub(body_start, body_start + length - 1)
    buffer = buffer:sub(body_start + length)
    local ok, msg = pcall(vim.json.decode, body)
    if ok then dispatch(msg) end
  end
end

stdin:read_start(function(err, data)
  if err then os.exit(1) end
  if not data then os.exit(0) end
  buffer = buffer .. data
  try_consume()
end)

uv.run()
