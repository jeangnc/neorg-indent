--- Buffer rendering functions.
--- Stateless utilities for applying indentation to buffer text.

local calculation = require("neorg.modules.external.indent.calculation")

local M = {}

--- Apply indentation by modifying buffer leading whitespace.
---@param bufid number buffer id
---@param row_start number 0-based inclusive
---@param row_end number 0-based exclusive
---@param indent_map table<number, table> row -> { level, continuation_indent }
---@param indent_per_level number spaces per indent level
---@param opts? table { preserve_modified: boolean }
function M.apply_indent(bufid, row_start, row_end, indent_map, indent_per_level, opts)
    opts = opts or {}
    local was_modified = vim.bo[bufid].modified

    for row = row_start, row_end - 1 do
        local desired = calculation.desired_indent_for_info(indent_map[row], indent_per_level)

        local lines = vim.api.nvim_buf_get_lines(bufid, row, row + 1, true)
        local line = lines[1]
        if line then
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

    if opts.preserve_modified then
        vim.bo[bufid].modified = was_modified
    end
end

--- Render indentation for the entire buffer.
---@param bufid number buffer id
---@param treesitter_module table the core.integrations.treesitter module
---@param indent_per_level number spaces per indent level
---@param opts? table { preserve_modified: boolean }
function M.render_buffer(bufid, treesitter_module, indent_per_level, opts)
    local document_root = treesitter_module.get_document_root(bufid)
    if not document_root then
        return
    end

    local line_count = vim.api.nvim_buf_line_count(bufid)
    local indent_map = calculation.build_indent_map(document_root, 0, line_count, bufid)
    M.apply_indent(bufid, 0, line_count, indent_map, indent_per_level, opts)
end

return M
