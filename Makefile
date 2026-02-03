ROCKS_TREE = .rocks
LUA_VERSION = 5.1

deps:
	luarocks --lua-version $(LUA_VERSION) --tree $(ROCKS_TREE) install --force nvim-treesitter-legacy-api
	luarocks --lua-version $(LUA_VERSION) --tree $(ROCKS_TREE) install neorg
	luarocks --lua-version $(LUA_VERSION) --tree $(ROCKS_TREE) install busted
	luarocks --lua-version $(LUA_VERSION) --tree $(ROCKS_TREE) install nlua

test:
	eval $$(luarocks path --tree $(ROCKS_TREE) --lua-version $(LUA_VERSION) --bin) && \
	busted

format:
	stylua -v --verify .
