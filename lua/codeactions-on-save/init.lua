---@class CodeActionsOnSave
---@field register Register Registers code actions for on save
---@field apply Apply Runs code actions for the given kinds against a buffer
---@field inspect Inspect Inspects code actions to see their 'kind'
local M = {}

local main = require("codeactions-on-save.main")
local inspect = require("codeactions-on-save.inspect")

M.register = main.register
M.apply = main.apply
M.inspect = inspect.inspect

return M
