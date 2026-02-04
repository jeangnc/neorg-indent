--- Pure indent-calculation functions.
--- No dependency on the Neorg `module` object.

local M = {}

local function get_line(bufid, row)
    local lines = vim.api.nvim_buf_get_lines(bufid, row, row + 1, true)
    return lines[1]
end

local function content_col_for_row(bufid, row)
    if not bufid then
        return 0
    end

    local line = get_line(bufid, row)
    if not line then
        return 0
    end

    local content_start = line:find("%S")
    if not content_start then
        return 0
    end

    return content_start - 1
end

local function is_list_node(node_type)
    return node_type:match("^unordered_list%d$") or node_type:match("^ordered_list%d$")
end

local function list_continuation_indent(list_node, row, bufid)
    local prefix_row = list_node:start()
    if prefix_row == row then
        return 0
    end

    local content_child = list_node:named_child(1)
    if content_child and content_child:type() == "detached_modifier_extension" then
        content_child = list_node:named_child(2)
    end
    if not content_child then
        return 0
    end

    local _, prefix_col = list_node:start()
    local _, content_col = content_child:start()
    local continuation_indent = content_col - prefix_col

    -- The paragraph node may start at the space before the text
    -- (e.g. after a detached_modifier_extension). Read the buffer
    -- to find the actual text start.
    if not bufid then
        return continuation_indent
    end

    local line = get_line(bufid, prefix_row)
    if not line then
        return continuation_indent
    end

    local after = line:sub(content_col + 1)
    local text_offset = after:find("%S")
    if text_offset and text_offset > 1 then
        continuation_indent = continuation_indent + text_offset - 1
    end

    return continuation_indent
end

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
function M.indent_level_for_row(document_root, row, bufid)
    local col = content_col_for_row(bufid, row)
    ---@diagnostic disable-next-line: undefined-field
    local node = document_root:named_descendant_for_range(row, col, row, col)
    if not node then
        return { level = 0, continuation_indent = 0 }
    end

    local level = 0
    local continuation_indent = 0
    local found_list = false
    local innermost_heading_level = nil
    local row_is_heading_prefix = false

    local cur = node
    while cur do
        local ntype = cur:type()

        local heading_n = ntype:match("^heading(%d)$")
        if heading_n then
            local prefix_row = cur:start()
            if prefix_row == row then
                row_is_heading_prefix = true
            else
                level = level + 1
                if not innermost_heading_level then
                    innermost_heading_level = tonumber(heading_n)
                end
            end
        end

        if is_list_node(ntype) then
            if not found_list then
                -- Innermost list: don't add a level so list markers
                -- sit at the same indent as sibling paragraphs.
                continuation_indent = list_continuation_indent(cur, row, bufid)
                found_list = true
            else
                -- Outer lists contribute a full indent level.
                level = level + 1
            end
        end

        cur = cur:parent()
    end

    local conceal_compensation = (not row_is_heading_prefix and innermost_heading_level) or 0

    return { level = level, continuation_indent = continuation_indent, conceal_compensation = conceal_compensation }
end

function M.desired_indent_for_info(info, indent_per_level)
    if not info then
        return 0
    end

    return info.level * indent_per_level + info.continuation_indent + (info.conceal_compensation or 0)
end

--- Build a map of row -> { level, continuation_indent } for the given range.
---@param document_root userdata treesitter node
---@param row_start number 0-based inclusive
---@param row_end number 0-based exclusive
---@param bufid? number buffer id — passed to indent_level_for_row
---@return table<number, table> indent_map
function M.build_indent_map(document_root, row_start, row_end, bufid)
    local indent_map = {}

    for row = row_start, row_end - 1 do
        local info = M.indent_level_for_row(document_root, row, bufid)
        if M.desired_indent_for_info(info, 1) > 0 then
            indent_map[row] = info
        end
    end

    return indent_map
end

return M
