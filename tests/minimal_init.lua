local cwd = vim.fn.getcwd()
vim.opt.runtimepath:prepend(cwd)
vim.opt.runtimepath:prepend(cwd .. "/.tests/plenary.nvim")
package.path = package.path .. ";" .. cwd .. "/tests/?.lua"
vim.cmd("runtime plugin/plenary.vim")
