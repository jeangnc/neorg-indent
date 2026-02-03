--[[
    file: external.indent
    title: Hierarchical Indentation for Norg Files
    description: Adds indentation to nested headings and lists by modifying buffer whitespace.
    summary: Indents nested content by inserting leading whitespace into the buffer.
    ---
`external.indent` adds hierarchical indentation to `.norg` files by inserting real
leading whitespace into the buffer. Headings at level 2+ and nested lists are indented
proportionally to their depth, making document structure visually clear.

Multi-line list items get continuation-line alignment so that wrapped text lines up
with the content start (after the prefix marker).
--]]

local neorg = require("neorg.core")
local modules = neorg.modules

local module = modules.create("external.indent")

module.setup = function()
    return {
        success = true,
        requires = {
            "core.autocommands",
            "core.integrations.treesitter",
        },
    }
end

module.config.public = {
    -- Number of spaces per indentation level.
    indent_per_level = 4,
}

module.private = {
    is_reindenting = false,
    rerendering_scheduled = {},
    attached_buffers = {},
}

--- Compute the indent level for a row by walking up from the deepest node
--- and accumulating contributions from headings and lists.
---
--- Each heading adds 1 level of indent to its content.
--- Each list (unordered/ordered) adds 1 level.
--- A heading's prefix line gets its parent headings' contributions only.
---
--- Returns a table with level and continuation_indent.
--- continuation_indent is the extra columns needed for list continuation lines
--- (lines within a list item that are not the prefix line).
---@param document_root userdata treesitter node
---@param row number 0-based row
---@param bufid? number buffer id — when provided, the actual content column is used
---@return table { level: number, continuation_indent: number }
local function indent_level_for_row(document_root, row, bufid)
    local col = 0
    if bufid then
        local lines = vim.api.nvim_buf_get_lines(bufid, row, row + 1, true)
        if lines[1] then
            local content_start = lines[1]:find("%S")
            if content_start then
                col = content_start - 1
            end
        end
    end
    local node = document_root:named_descendant_for_range(row, col, row, col)
    if not node then
        return { level = 0, continuation_indent = 0 }
    end

    local level = 0
    local continuation_indent = 0
    local found_list = false

    local cur = node
    while cur do
        local ntype = cur:type()

        local heading_num = ntype:match("^heading(%d)$")
        if heading_num then
            local prefix_row = cur:start()
            if prefix_row ~= row then
                level = level + 1
            end
        end

        if ntype:match("^unordered_list%d$") or ntype:match("^ordered_list%d$") then
            level = level + 1

            -- Only compute continuation indent for the innermost list node
            -- when we're not on its prefix line (i.e. a wrapped paragraph line).
            if not found_list then
                local prefix_row = cur:start()
                if prefix_row ~= row then
                    local content_child = cur:named_child(1)
                    if content_child and content_child:type() == "detached_modifier_extension" then
                        content_child = cur:named_child(2)
                    end
                    if content_child then
                        local _, prefix_col = cur:start()
                        local _, content_col = content_child:start()
                        continuation_indent = content_col - prefix_col
                    end
                end
                found_list = true
            end
        end

        cur = cur:parent()
    end

    return { level = level, continuation_indent = continuation_indent }
end

--- Build a map of row -> { level, continuation_indent } for the given range.
---@param document_root userdata treesitter node
---@param row_start number 0-based inclusive
---@param row_end number 0-based exclusive
---@param bufid? number buffer id — passed to indent_level_for_row
---@return table<number, table> indent_map
local function build_indent_map(document_root, row_start, row_end, bufid)
    local indent_map = {}

    for row = row_start, row_end - 1 do
        local info = indent_level_for_row(document_root, row, bufid)
        if info.level > 0 or info.continuation_indent > 0 then
            indent_map[row] = info
        end
    end

    return indent_map
end

--- Apply indentation by modifying buffer leading whitespace.
---@param bufid number buffer id
---@param row_start number 0-based inclusive
---@param row_end number 0-based exclusive
---@param indent_map table<number, table> row -> { level, continuation_indent }
---@param opts? table { preserve_modified: boolean }
local function apply_indent(bufid, row_start, row_end, indent_map, opts)
    opts = opts or {}
    local indent_per_level = module.config.public.indent_per_level
    local was_modified = vim.bo[bufid].modified

    module.private.is_reindenting = true

    for row = row_start, row_end - 1 do
        local info = indent_map[row]
        local desired = 0
        if info then
            desired = info.level * indent_per_level + info.continuation_indent
        end

        local lines = vim.api.nvim_buf_get_lines(bufid, row, row + 1, true)
        if lines[1] then
            local line = lines[1]
            -- Skip empty/whitespace-only lines to avoid creating trailing whitespace.
            local content_start = line:find("%S")
            if not content_start then
                -- Line has no content — ensure it's truly empty.
                if #line > 0 then
                    vim.api.nvim_buf_set_text(bufid, row, 0, row, #line, { "" })
                end
            else
                local current_ws = content_start - 1
                if current_ws ~= desired then
                    vim.api.nvim_buf_set_text(bufid, row, 0, row, current_ws, { (" "):rep(desired) })
                end
            end
        end
    end

    module.private.is_reindenting = false

    if opts.preserve_modified then
        vim.bo[bufid].modified = was_modified
    end
end

--- Compute the desired indent (in spaces) for a single row.
--- Used by both apply_indent and indentexpr.
---@param bufid number buffer id
---@param row number 0-based row
---@return number desired indent in spaces
local function desired_indent_for_row(bufid, row)
    local treesitter_module = module.required["core.integrations.treesitter"]
    local document_root = treesitter_module.get_document_root(bufid)
    if not document_root then
        return 0
    end

    local info = indent_level_for_row(document_root, row, bufid)
    return info.level * module.config.public.indent_per_level + info.continuation_indent
end

--- indentexpr function called by Neovim's = operator.
--- Returns the desired indent for the given line number (1-based, from v:lnum).
---@param bufid number buffer id
---@return number indent in spaces
local function indentexpr(bufid)
    local lnum = vim.v.lnum
    return desired_indent_for_row(bufid, lnum - 1)
end

--- Render indentation for the entire buffer.
---@param bufid number buffer id
---@param opts? table { preserve_modified: boolean }
local function render_buffer(bufid, opts)
    local treesitter_module = module.required["core.integrations.treesitter"]
    local document_root = treesitter_module.get_document_root(bufid)
    if not document_root then
        return
    end

    local line_count = vim.api.nvim_buf_line_count(bufid)
    local indent_map = build_indent_map(document_root, 0, line_count, bufid)
    apply_indent(bufid, 0, line_count, indent_map, opts)
end

local function render_all_scheduled()
    for bufid, _ in pairs(module.private.rerendering_scheduled) do
        if vim.api.nvim_buf_is_valid(bufid) then
            render_buffer(bufid)
        end
    end
    module.private.rerendering_scheduled = {}
end

local function schedule_rendering(bufid)
    if module.private.is_reindenting then
        return
    end

    local not_scheduled = vim.tbl_isempty(module.private.rerendering_scheduled)
    module.private.rerendering_scheduled[bufid] = true
    if not_scheduled then
        vim.schedule(render_all_scheduled)
    end
end

local function attach_buffer(bufid)
    if module.private.attached_buffers[bufid] then
        return
    end
    module.private.attached_buffers[bufid] = true

    local attach_succeeded = vim.api.nvim_buf_attach(bufid, true, {
        on_lines = function(_tag, buf)
            schedule_rendering(buf)
        end,
    })

    if not attach_succeeded then
        module.private.attached_buffers[bufid] = nil
        return
    end

    local ok, language_tree = pcall(vim.treesitter.get_parser, bufid, "norg")
    if ok and language_tree then
        language_tree:register_cbs({
            on_changedtree = function()
                schedule_rendering(bufid)
            end,
        })
    end

    -- Disable core.esupports.indent so it doesn't override our indentexpr.
    -- Done here (not in module.load) because module load order is non-deterministic.
    local core_indent = modules.loaded_modules["core.esupports.indent"]
    if core_indent and core_indent.on_event then
        core_indent.on_event = function() end
    end

    -- Override indentexpr so that = uses our indent logic.
    vim.bo[bufid].indentexpr = ("v:lua.require'neorg'.modules.get_module('external.indent').indentexpr(%d)"):format(
        bufid
    )

    -- Initial indent — preserve the modified flag so opening a file
    -- doesn't mark it as unsaved.
    render_buffer(bufid, { preserve_modified = true })
end

--- Event handling

local function handle_init_event(event)
    attach_buffer(event.buffer)
end

local event_handlers = {
    ["core.autocommands.events.filetype"] = handle_init_event,
    ["core.autocommands.events.bufreadpost"] = handle_init_event,
}

module.on_event = function(event)
    if event.referrer == "core.autocommands" and vim.bo[event.buffer].ft ~= "norg" then
        return
    end

    local handler = event_handlers[event.type]
    if handler then
        handler(event)
    end
end

module.load = function()
    module.required["core.autocommands"].enable_autocommand("FileType", true)
    module.required["core.autocommands"].enable_autocommand("BufReadPost")
end

module.events.subscribed = {
    ["core.autocommands"] = {
        filetype = true,
        bufreadpost = true,
    },
}

-- Expose internal functions for testing and indentexpr
module.public.indent_level_for_row = indent_level_for_row
module.public.indentexpr = indentexpr
module.public.apply_indent = function(bufid, row_start, row_end, indent_map, opts)
    apply_indent(bufid, row_start, row_end, indent_map, opts)
end

return module
