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

local calculation = require("neorg.modules.external.indent.calculation")
local renderer = require("neorg.modules.external.indent.renderer")

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

--- Render indentation for a buffer, guarding against re-entrant calls.
---@param bufid number buffer id
---@param opts? table { preserve_modified: boolean }
local function render_buffer(bufid, opts)
    local treesitter_module = module.required["core.integrations.treesitter"]
    module.private.is_reindenting = true
    renderer.render_buffer(bufid, treesitter_module, module.config.public.indent_per_level, opts)
    module.private.is_reindenting = false
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

    local was_empty = vim.tbl_isempty(module.private.rerendering_scheduled)
    module.private.rerendering_scheduled[bufid] = true
    if was_empty then
        vim.schedule(render_all_scheduled)
    end
end

--- Compute the desired indent (in spaces) for a single row.
--- Used by indentexpr.
---@param bufid number buffer id
---@param row number 0-based row
---@return number desired indent in spaces
local function desired_indent_for_row(bufid, row)
    local treesitter_module = module.required["core.integrations.treesitter"]
    local document_root = treesitter_module.get_document_root(bufid)
    if not document_root then
        return 0
    end

    local info = calculation.indent_level_for_row(document_root, row, bufid)
    return calculation.desired_indent_for_info(info, module.config.public.indent_per_level)
end

--- indentexpr function called by Neovim's = operator.
--- Returns the desired indent for the given line number (1-based, from v:lnum).
---@param bufid number buffer id
---@return number indent in spaces
local function indentexpr(bufid)
    local lnum = vim.v.lnum
    return desired_indent_for_row(bufid, lnum - 1)
end

local function attach_buffer(bufid)
    if module.private.attached_buffers[bufid] then
        return
    end
    module.private.attached_buffers[bufid] = true

    local attach_succeeded = vim.api.nvim_buf_attach(bufid, true, {
        on_lines = function(_, buf)
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

    -- Override reindent_range and buffer_set_line_indent so that core.promo
    -- (which calls these directly) uses our indent logic instead of the
    -- built-in one.
    if core_indent and core_indent.public then
        core_indent.public.reindent_range = function(buffer, _, _)
            if vim.api.nvim_buf_is_valid(buffer) then
                render_buffer(buffer)
            end
        end

        core_indent.public.buffer_set_line_indent = function() end
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

module.public.indentexpr = indentexpr

return module
