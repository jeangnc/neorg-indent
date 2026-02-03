ROCKS_TREE = .rocks
LUA_VERSION = 5.1
LAZY_DIR = $(HOME)/.local/share/nvim/lazy

deps:
	luarocks --lua-version $(LUA_VERSION) --tree $(ROCKS_TREE) install busted
	luarocks --lua-version $(LUA_VERSION) --tree $(ROCKS_TREE) install nlua

LAZY_LPATH = $(shell for d in $(LAZY_DIR)/*/lua; do printf '%s/?.lua;%s/?/init.lua;' "$$d" "$$d"; done)

test:
	eval $$(luarocks path --tree $(ROCKS_TREE) --lua-version $(LUA_VERSION) --bin) && \
	LUA_PATH="$$LUA_PATH;$(LAZY_LPATH)" \
	busted

format:
	stylua -v --verify .
