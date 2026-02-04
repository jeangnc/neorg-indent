local M = {}

--- Disable core.esupports.indent by replacing its functions with our own.
---@param core_indent table the core.esupports.indent module table
---@param render_buffer_fn function(bufid) re-render a buffer's indentation
---@param indentexpr_fn function() indentexpr replacement
function M.disable_core_indent(core_indent, render_buffer_fn, indentexpr_fn)
    core_indent.on_event = function() end

    core_indent.public.reindent_range = function(buffer, _, _)
        if vim.api.nvim_buf_is_valid(buffer) then
            render_buffer_fn(buffer)
        end
    end

    core_indent.public.buffer_set_line_indent = function() end

    core_indent.public.indentexpr = indentexpr_fn
end

return M
