require("neorg.tests")

local calculation = require("neorg.modules.external.indent.calculation")
local renderer = require("neorg.modules.external.indent.renderer")

--- Helper: parse norg content and return the document root TSNode.
---@param content string norg source text
---@return userdata root TSNode
---@return number bufnr
local function parse_norg(content)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, true, vim.split(content, "\n"))
    -- Don't set filetype — avoids triggering attach_buffer autocommands
    -- which leak parser state and exhaust the parser pool in tests.
    local parser = vim.treesitter.get_parser(buf, "norg")
    local tree = parser:parse()[1]
    return tree:root(), buf
end

--- Helper: clean up buffer after test.
local function cleanup_buf(buf)
    vim.api.nvim_buf_delete(buf, { force = true })
end

local INDENT_PER_LEVEL = 4

describe("external.indent", function()
    describe("indent_level_for_row (pre-indented content)", function()
        it("returns level 3 for pre-indented list under heading2", function()
            local root, buf = parse_norg("* Heading 1\n    ** Heading 2\n        - List item")
            local info = calculation.indent_level_for_row(root, 2, buf)

            assert.equal(2, info.level)

            cleanup_buf(buf)
        end)

        it("returns level 3 for pre-indented nested list item", function()
            local root, buf =
                parse_norg("* Heading 1\n    ** Heading 2\n        - List item\n            -- Nested item")
            local info = calculation.indent_level_for_row(root, 3, buf)

            assert.equal(3, info.level)

            cleanup_buf(buf)
        end)

        it("returns level 2 for pre-indented content under heading2", function()
            local root, buf = parse_norg("* Heading 1\n    ** Heading 2\n        Content under h2")
            local info = calculation.indent_level_for_row(root, 2, buf)

            assert.equal(2, info.level)

            cleanup_buf(buf)
        end)

        it("returns level 2 for pre-indented heading3 prefix under heading2", function()
            local root, buf = parse_norg("* Heading 1\n    ** Heading 2\n        *** Heading 3")
            local info = calculation.indent_level_for_row(root, 2, buf)

            assert.equal(2, info.level)

            cleanup_buf(buf)
        end)

        it("returns level 3 for pre-indented content under heading3", function()
            local root, buf =
                parse_norg("* Heading 1\n    ** Heading 2\n        *** Heading 3\n            Content under h3")
            local info = calculation.indent_level_for_row(root, 3, buf)

            assert.equal(3, info.level)

            cleanup_buf(buf)
        end)

        it("returns level 3 for pre-indented heading4 prefix under heading3", function()
            local root, buf =
                parse_norg("* Heading 1\n    ** Heading 2\n        *** Heading 3\n            **** Heading 4")
            local info = calculation.indent_level_for_row(root, 3, buf)

            assert.equal(3, info.level)

            cleanup_buf(buf)
        end)

        it("returns level 4 for pre-indented content under heading4", function()
            local content =
                "* Heading 1\n    ** Heading 2\n        *** Heading 3\n            **** Heading 4\n                Content under h4"
            local root, buf = parse_norg(content)
            local info = calculation.indent_level_for_row(root, 4, buf)

            assert.equal(4, info.level)

            cleanup_buf(buf)
        end)

        it("returns level 4 for pre-indented list item under heading4", function()
            local content =
                "* Heading 1\n    ** Heading 2\n        *** Heading 3\n            **** Heading 4\n                - List item"
            local root, buf = parse_norg(content)
            local info = calculation.indent_level_for_row(root, 4, buf)

            assert.equal(4, info.level)

            cleanup_buf(buf)
        end)

        it("returns continuation_indent for pre-indented continuation line", function()
            local root, buf = parse_norg("* Heading 1\n    - List item\n      continued text")
            local info = calculation.indent_level_for_row(root, 2, buf)

            assert.is_true(info.continuation_indent > 0)

            cleanup_buf(buf)
        end)
    end)

    describe("indent_level_for_row", function()
        it("returns level 0 for heading1 prefix line", function()
            local root, buf = parse_norg("* Heading 1")
            local info = calculation.indent_level_for_row(root, 0, buf)

            assert.equal(0, info.level)

            cleanup_buf(buf)
        end)

        it("returns level 1 for content under heading1", function()
            local root, buf = parse_norg("* Heading 1\nSome content")
            local info = calculation.indent_level_for_row(root, 1, buf)

            assert.equal(1, info.level)

            cleanup_buf(buf)
        end)

        it("returns level 1 for heading2 prefix under heading1", function()
            local root, buf = parse_norg("* Heading 1\n** Heading 2")
            local info = calculation.indent_level_for_row(root, 1, buf)

            assert.equal(1, info.level)

            cleanup_buf(buf)
        end)

        it("returns level 2 for content under heading2", function()
            local root, buf = parse_norg("* Heading 1\n** Heading 2\nContent under h2")
            local info = calculation.indent_level_for_row(root, 2, buf)

            assert.equal(2, info.level)

            cleanup_buf(buf)
        end)

        it("returns level 2 for list item under heading2", function()
            local root, buf = parse_norg("* Heading 1\n** Heading 2\n- List item")
            local info = calculation.indent_level_for_row(root, 2, buf)

            assert.equal(2, info.level)

            cleanup_buf(buf)
        end)

        it("returns level 3 for nested list item", function()
            local root, buf = parse_norg("* Heading 1\n** Heading 2\n- List item\n-- Nested item")
            local info = calculation.indent_level_for_row(root, 3, buf)

            assert.equal(3, info.level)

            cleanup_buf(buf)
        end)

        it("returns level 2 for heading3 prefix under heading2", function()
            local root, buf = parse_norg("* Heading 1\n** Heading 2\n*** Heading 3")
            local info = calculation.indent_level_for_row(root, 2, buf)

            assert.equal(2, info.level)

            cleanup_buf(buf)
        end)

        it("returns level 3 for content under heading3", function()
            local root, buf = parse_norg("* Heading 1\n** Heading 2\n*** Heading 3\nContent under h3")
            local info = calculation.indent_level_for_row(root, 3, buf)

            assert.equal(3, info.level)

            cleanup_buf(buf)
        end)

        it("returns level 3 for heading4 prefix under heading3", function()
            local root, buf = parse_norg("* Heading 1\n** Heading 2\n*** Heading 3\n**** Heading 4")
            local info = calculation.indent_level_for_row(root, 3, buf)

            assert.equal(3, info.level)

            cleanup_buf(buf)
        end)

        it("returns level 4 for content under heading4", function()
            local content = "* Heading 1\n** Heading 2\n*** Heading 3\n**** Heading 4\nContent under h4"
            local root, buf = parse_norg(content)
            local info = calculation.indent_level_for_row(root, 4, buf)

            assert.equal(4, info.level)

            cleanup_buf(buf)
        end)

        it("returns level 4 for list item under heading4", function()
            local root, buf = parse_norg("* Heading 1\n** Heading 2\n*** Heading 3\n**** Heading 4\n- List item")
            local info = calculation.indent_level_for_row(root, 4, buf)

            assert.equal(4, info.level)

            cleanup_buf(buf)
        end)

        it("inherits parent heading level for empty line between headings", function()
            local root, buf = parse_norg("* Heading 1\n\n** Heading 2")
            local info = calculation.indent_level_for_row(root, 1, buf)

            assert.equal(1, info.level)

            cleanup_buf(buf)
        end)

        it("returns continuation_indent 0 for non-list lines", function()
            local root, buf = parse_norg("* Heading 1\nSome content")
            local info = calculation.indent_level_for_row(root, 1, buf)

            assert.equal(0, info.continuation_indent)

            cleanup_buf(buf)
        end)

        it("returns same level for list item and sibling paragraph under heading", function()
            local root, buf = parse_norg("* Heading 1\nParagraph text\n- List item")
            local para_info = calculation.indent_level_for_row(root, 1, buf)
            local list_info = calculation.indent_level_for_row(root, 2, buf)

            assert.equal(para_info.level, list_info.level)

            cleanup_buf(buf)
        end)
    end)

    describe("conceal_compensation", function()
        it("returns conceal_compensation 1 for content under h1", function()
            local root, buf = parse_norg("* Heading 1\nSome content")
            local info = calculation.indent_level_for_row(root, 1, buf)

            assert.equal(1, info.conceal_compensation)

            cleanup_buf(buf)
        end)

        it("returns conceal_compensation 2 for content under h2", function()
            local root, buf = parse_norg("* Heading 1\n** Heading 2\nContent under h2")
            local info = calculation.indent_level_for_row(root, 2, buf)

            assert.equal(2, info.conceal_compensation)

            cleanup_buf(buf)
        end)

        it("returns conceal_compensation 3 for content under h3", function()
            local root, buf = parse_norg("* Heading 1\n** Heading 2\n*** Heading 3\nContent under h3")
            local info = calculation.indent_level_for_row(root, 3, buf)

            assert.equal(3, info.conceal_compensation)

            cleanup_buf(buf)
        end)

        it("returns conceal_compensation 4 for content under h4", function()
            local content = "* Heading 1\n** Heading 2\n*** Heading 3\n**** Heading 4\nContent under h4"
            local root, buf = parse_norg(content)
            local info = calculation.indent_level_for_row(root, 4, buf)

            assert.equal(4, info.conceal_compensation)

            cleanup_buf(buf)
        end)

        it("returns conceal_compensation 0 for heading prefix lines", function()
            local root, buf = parse_norg("* Heading 1\n** Heading 2")
            local h1_info = calculation.indent_level_for_row(root, 0, buf)
            local h2_info = calculation.indent_level_for_row(root, 1, buf)

            assert.equal(0, h1_info.conceal_compensation)
            assert.equal(0, h2_info.conceal_compensation)

            cleanup_buf(buf)
        end)
    end)

    describe("continuation lines", function()
        it("returns continuation_indent 0 for list item prefix line", function()
            local root, buf = parse_norg("- List item")
            local info = calculation.indent_level_for_row(root, 0, buf)

            assert.equal(0, info.continuation_indent)

            cleanup_buf(buf)
        end)

        it("returns continuation_indent for second line of list item", function()
            local root, buf = parse_norg("- List item\n  continued text")
            local info = calculation.indent_level_for_row(root, 1, buf)

            assert.is_true(info.continuation_indent > 0)

            cleanup_buf(buf)
        end)

        it("aligns continuation after '- ' prefix with +2 columns", function()
            local root, buf = parse_norg("- List item\n  continued text")
            local info = calculation.indent_level_for_row(root, 1, buf)

            assert.equal(2, info.continuation_indent)

            cleanup_buf(buf)
        end)

        it("aligns continuation after detached_modifier_extension with text start", function()
            local root, buf = parse_norg("- ( ) Task text\n      continued")
            local prefix_info = calculation.indent_level_for_row(root, 0, buf)
            local cont_info = calculation.indent_level_for_row(root, 1, buf)

            assert.equal(0, prefix_info.continuation_indent)
            assert.is_true(cont_info.continuation_indent >= 6)

            cleanup_buf(buf)
        end)
    end)

    describe("apply_indent (buffer modification)", function()
        it("inserts leading whitespace for indented lines", function()
            local buf = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_lines(buf, 0, -1, true, {
                "* Heading 1",
                "Content under h1",
            })

            local indent_map = {
                [1] = { level = 1, continuation_indent = 0 },
            }

            renderer.apply_indent(buf, 0, 2, indent_map, INDENT_PER_LEVEL)

            local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, true)
            assert.equal("* Heading 1", lines[1])
            assert.equal("    Content under h1", lines[2])

            vim.api.nvim_buf_delete(buf, { force = true })
        end)

        it("does not modify lines with no indent info", function()
            local buf = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_lines(buf, 0, -1, true, {
                "* Heading 1",
            })

            renderer.apply_indent(buf, 0, 1, {}, INDENT_PER_LEVEL)

            local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, true)
            assert.equal("* Heading 1", lines[1])

            vim.api.nvim_buf_delete(buf, { force = true })
        end)

        it("adjusts existing whitespace to match desired indent", function()
            local buf = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_lines(buf, 0, -1, true, {
                "  Content with wrong indent",
            })

            local indent_map = {
                [0] = { level = 2, continuation_indent = 0 },
            }

            renderer.apply_indent(buf, 0, 1, indent_map, INDENT_PER_LEVEL)

            local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, true)
            assert.equal("        Content with wrong indent", lines[1])

            vim.api.nvim_buf_delete(buf, { force = true })
        end)

        it("adds continuation_indent to the total indent", function()
            local buf = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_lines(buf, 0, -1, true, {
                "continuation line",
            })

            local indent_map = {
                [0] = { level = 1, continuation_indent = 2 },
            }

            renderer.apply_indent(buf, 0, 1, indent_map, INDENT_PER_LEVEL)

            local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, true)
            -- 1 * 4 + 2 = 6 spaces
            assert.equal("      continuation line", lines[1])

            vim.api.nvim_buf_delete(buf, { force = true })
        end)

        it("preserves modified flag after initial indent", function()
            local buf = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_lines(buf, 0, -1, true, {
                "Content",
            })
            vim.bo[buf].modified = false

            local indent_map = {
                [0] = { level = 1, continuation_indent = 0 },
            }

            renderer.apply_indent(buf, 0, 1, indent_map, INDENT_PER_LEVEL, { preserve_modified = true })

            assert.is_false(vim.bo[buf].modified)

            vim.api.nvim_buf_delete(buf, { force = true })
        end)
    end)
end)
