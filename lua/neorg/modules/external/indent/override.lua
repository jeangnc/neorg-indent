local M = {}

--- Disable core.esupports.indent by replacing its public functions with our own.
--- modules.await passes the module's public table directly.
---@param core_indent_public table the core.esupports.indent module's public table
---@param render_buffer_fn function(bufid) re-render a buffer's indentation
---@param indentexpr_fn function() indentexpr replacement
function M.disable_core_indent(core_indent_public, render_buffer_fn, indentexpr_fn)
    core_indent_public.reindent_range = function(buffer, _, _)
        if vim.api.nvim_buf_is_valid(buffer) then
            render_buffer_fn(buffer)
        end
    end

    core_indent_public.buffer_set_line_indent = function() end

    core_indent_public.indentexpr = indentexpr_fn
end

return M
