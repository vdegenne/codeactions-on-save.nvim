.PHONY: test

.tests/plenary.nvim:
	mkdir -p .tests
	git clone --depth 1 https://github.com/nvim-lua/plenary.nvim .tests/plenary.nvim

test: .tests/plenary.nvim
	nvim --headless --noplugin -u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory tests/spec { minimal_init = 'tests/minimal_init.lua' }"
