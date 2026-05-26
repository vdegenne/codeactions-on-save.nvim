local M = {}
local plugin = require("codeactions-on-save")

local server_path = vim.fn.fnamemodify("tests/fake_lsp/server.lua", ":p")
local active
local registered_patterns = {}

local function wait_initialized(client_id)
  local ok = vim.wait(5000, function()
    local c = vim.lsp.get_client_by_id(client_id)
    return c ~= nil and c.initialized == true
  end, 20)
  assert(ok, "fake LSP did not initialize")
end

local function dedent(text)
  local lines = vim.split(text, "\n", { plain = true })
  if #lines > 0 and lines[1] == "" then table.remove(lines, 1) end
  if #lines > 0 and lines[#lines]:match("^%s*$") then table.remove(lines) end

  local min_indent
  for _, line in ipairs(lines) do
    if line ~= "" then
      local indent = #(line:match("^%s*") or "")
      if min_indent == nil or indent < min_indent then min_indent = indent end
    end
  end
  min_indent = min_indent or 0

  for i, line in ipairs(lines) do
    lines[i] = line:sub(min_indent + 1)
  end
  return lines
end

function M.text(s)
  return dedent(s)
end

local function check_no_upvalues(fn)
  local i = 1
  while true do
    local name = debug.getupvalue(fn, i)
    if not name then return end
    if name ~= "_ENV" then
      error("scenario must not capture upvalues from outside; got '" .. name .. "'", 3)
    end
    i = i + 1
  end
end

local function dump_scenario(fn)
  check_no_upvalues(fn)
  local path = vim.fn.tempname()
  local f = assert(io.open(path, "wb"))
  f:write(string.dump(fn))
  f:close()
  return path
end

function M.user_setup(configs)
  for _, c in ipairs(configs) do
    plugin.register(c.pattern, c.kinds, c.timeout_ms)
    for _, p in ipairs(c.pattern) do
      table.insert(registered_patterns, p)
    end
  end
end

function M.buffer(text)
  local tmpdir = vim.fn.tempname()
  vim.fn.mkdir(tmpdir, "p")
  local file = tmpdir .. "/repro.fake"
  vim.fn.writefile(dedent(text), file)

  vim.cmd("edit " .. vim.fn.fnameescape(file))
  active = { bufnr = vim.api.nvim_get_current_buf(), tmpdir = tmpdir }
end

function M.fake_lsp(scenario_fn)
  assert(active and active.bufnr, "h.fake_lsp requires h.buffer() first")

  local scenario_path = dump_scenario(scenario_fn)
  local client_id = assert(vim.lsp.start({
    name = "fake-lsp",
    cmd = { "nvim", "--headless", "-l", server_path, scenario_path },
    root_dir = active.tmpdir,
  }))
  wait_initialized(client_id)
  vim.lsp.buf_attach_client(active.bufnr, client_id)

  active.client_id = client_id
  active.scenario_path = scenario_path
end

function M.lines()
  return vim.api.nvim_buf_get_lines(active.bufnr, 0, -1, false)
end

function M.cleanup()
  for _, pattern in ipairs(registered_patterns) do
    pcall(vim.api.nvim_clear_autocmds, { event = "BufWritePre", pattern = pattern })
  end
  registered_patterns = {}

  if not active then return end
  if active.client_id then
    local client = vim.lsp.get_client_by_id(active.client_id)
    if client then client:stop(true) end
  end
  pcall(vim.api.nvim_buf_delete, active.bufnr, { force = true })
  pcall(vim.fn.delete, active.tmpdir, "rf")
  if active.scenario_path then pcall(vim.fn.delete, active.scenario_path) end
  active = nil
end

return M
