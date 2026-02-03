ROCKS_TREE ?= .rocks
LUA_VERSION ?= 5.1
ROCKSPEC ?= neorg-indent-scm-1.rockspec
NEORG_DIR ?= $(HOME)/.local/share/nvim/lazy/neorg/lua
NEORG_LPATH = $(NEORG_DIR)/?.lua;$(NEORG_DIR)/?/init.lua

test:
	eval $$(luarocks path --tree $(ROCKS_TREE) --lua-version $(LUA_VERSION) --bin) && \
	LUA_PATH="$(NEORG_LPATH);$$LUA_PATH" \
	luarocks --tree $(ROCKS_TREE) --lua-version $(LUA_VERSION) test $(ROCKSPEC)

format:
	stylua -v --verify .
