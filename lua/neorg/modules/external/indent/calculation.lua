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

local function list_node_level(node_type)
    local n = node_type:match("^unordered_list(%d)$") or node_type:match("^ordered_list(%d)$")
    return n and tonumber(n) or nil
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

--- Compute the indent info for a row by walking up from the deepest node
--- and accumulating contributions from headings and lists.
---
--- Each heading adds its level number to heading_contributions.
--- Each list (unordered/ordered) contributes to list_nesting.
--- A heading's prefix line gets its parent headings' contributions only.
---
--- Returns a table with heading_contributions, list_nesting, continuation_indent,
--- and conceal_compensation.
---@param document_root userdata treesitter node
---@param row number 0-based row
---@param bufid? number buffer id — when provided, the actual content column is used
---@return table { heading_contributions: table, list_nesting: number, continuation_indent: number, conceal_compensation: number }
function M.indent_level_for_row(document_root, row, bufid)
    local col = content_col_for_row(bufid, row)
    ---@diagnostic disable-next-line: undefined-field
    local node = document_root:named_descendant_for_range(row, col, row, col)
    if not node then
        return { heading_contributions = {}, list_nesting = 0, continuation_indent = 0, conceal_compensation = 0 }
    end

    local heading_contributions = {}
    local list_nesting = 0
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
                table.insert(heading_contributions, tonumber(heading_n))
                if not innermost_heading_level then
                    innermost_heading_level = tonumber(heading_n)
                end
            end
        end

        local list_n = list_node_level(ntype)
        if list_n then
            if not found_list then
                continuation_indent = list_continuation_indent(cur, row, bufid)
                list_nesting = list_n - 1
                found_list = true
            end
        end

        cur = cur:parent()
    end

    -- heading_contributions are collected inner-to-outer; reverse for outer-to-inner order
    local reversed = {}
    for i = #heading_contributions, 1, -1 do
        reversed[#reversed + 1] = heading_contributions[i]
    end

    local conceal_compensation = (not row_is_heading_prefix and innermost_heading_level) or 0

    return {
        heading_contributions = reversed,
        list_nesting = list_nesting,
        continuation_indent = continuation_indent,
        conceal_compensation = conceal_compensation,
    }
end

function M.desired_indent_for_info(info, config)
    if not info then
        return 0
    end

    local total = 0
    for _, h in ipairs(info.heading_contributions) do
        total = total + (config.heading_indent and config.heading_indent[h] or config.indent_per_level)
    end
    for i = 1, info.list_nesting do
        total = total + (config.list_indent and config.list_indent[i] or config.indent_per_level)
    end
    return total + info.continuation_indent + (info.conceal_compensation or 0)
end

local function has_indent(info)
    return #info.heading_contributions > 0
        or info.list_nesting > 0
        or info.continuation_indent > 0
        or (info.conceal_compensation or 0) > 0
end

--- Build a map of row -> indent info for the given range.
---@param document_root userdata treesitter node
---@param row_start number 0-based inclusive
---@param row_end number 0-based exclusive
---@param bufid? number buffer id — passed to indent_level_for_row
---@return table<number, table> indent_map
function M.build_indent_map(document_root, row_start, row_end, bufid)
    local indent_map = {}

    for row = row_start, row_end - 1 do
        local info = M.indent_level_for_row(document_root, row, bufid)
        if has_indent(info) then
            indent_map[row] = info
        end
    end

    return indent_map
end

return M
