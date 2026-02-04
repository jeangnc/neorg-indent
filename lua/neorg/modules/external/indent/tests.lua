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

    describe("promote/demote (heading prefix change with stale whitespace)", function()
        it("computes correct indent levels after promote (h2 → h3)", function()
            -- Simulates core.promo promoting h2 to h3: the *** prefix is in place
            -- but whitespace still reflects the old h2 level (4 spaces).
            local root, buf = parse_norg("* Heading 1\n    *** Heading 3\n        Content under h3")
            local h3_info = calculation.indent_level_for_row(root, 1, buf)
            local content_info = calculation.indent_level_for_row(root, 2, buf)

            -- h3 prefix under h1 → level 1 (indented once as child of h1)
            assert.equal(1, h3_info.level)
            -- Content under h3 → level 2 + conceal_compensation
            assert.equal(2, content_info.level)

            cleanup_buf(buf)
        end)

        it("computes correct indent levels after demote (h2 → h1)", function()
            -- Simulates core.promo demoting h2 to h1: the * prefix is in place
            -- but whitespace still reflects the old h2 level (4 spaces).
            local root, buf = parse_norg("    * Heading 1\n        Content under h1")
            local h1_info = calculation.indent_level_for_row(root, 0, buf)
            local content_info = calculation.indent_level_for_row(root, 1, buf)

            -- h1 prefix → level 0 (top level)
            assert.equal(0, h1_info.level)
            -- Content under h1 → level 1
            assert.equal(1, content_info.level)

            cleanup_buf(buf)
        end)

        it("render corrects whitespace after simulated promote (h2 → h3)", function()
            -- Buffer state after core.promo changes ** to *** but hasn't re-indented.
            local buf = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_lines(buf, 0, -1, true, {
                "* Heading 1",
                "    *** Heading 3",
                "        Content under h3",
            })
            local parser = vim.treesitter.get_parser(buf, "norg")
            local tree = parser:parse()[1]
            local root = tree:root()

            local line_count = vim.api.nvim_buf_line_count(buf)
            local indent_map = calculation.build_indent_map(root, 0, line_count, buf)
            renderer.apply_indent(buf, 0, line_count, indent_map, INDENT_PER_LEVEL)

            local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, true)
            -- h1 stays at column 0
            assert.equal("* Heading 1", lines[1])
            -- h3 prefix under h1 → 1 level = 4 spaces
            assert.equal("    *** Heading 3", lines[2])
            -- Content under h3 → 2 levels + conceal_compensation(3) = 11 spaces
            assert.equal("           Content under h3", lines[3])

            vim.api.nvim_buf_delete(buf, { force = true })
        end)

        it("render corrects whitespace after simulated demote (h2 → h1)", function()
            -- Buffer state after core.promo changes ** to * but hasn't re-indented.
            local buf = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_lines(buf, 0, -1, true, {
                "    * Heading 1",
                "        Content under h1",
            })
            local parser = vim.treesitter.get_parser(buf, "norg")
            local tree = parser:parse()[1]
            local root = tree:root()

            local line_count = vim.api.nvim_buf_line_count(buf)
            local indent_map = calculation.build_indent_map(root, 0, line_count, buf)
            renderer.apply_indent(buf, 0, line_count, indent_map, INDENT_PER_LEVEL)

            local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, true)
            -- h1 prefix → column 0 (no indent)
            assert.equal("* Heading 1", lines[1])
            -- Content under h1 → 1 level + conceal_compensation(1) = 5 spaces
            assert.equal("     Content under h1", lines[2])

            vim.api.nvim_buf_delete(buf, { force = true })
        end)
    end)

    describe("override", function()
        local override = require("neorg.modules.external.indent.override")

        it("replaces on_event with a no-op", function()
            local core_indent = {
                on_event = function()
                    return "original"
                end,
                public = {
                    reindent_range = function() end,
                    buffer_set_line_indent = function() end,
                    indentexpr = function() end,
                },
            }

            override.disable_core_indent(core_indent, function() end, function() end)

            assert.is_nil(core_indent.on_event())
        end)

        it("redirects reindent_range to render_buffer_fn", function()
            local called_with = nil
            local render_buffer_fn = function(buffer)
                called_with = buffer
            end

            local core_indent = {
                on_event = function() end,
                public = {
                    reindent_range = function() end,
                    buffer_set_line_indent = function() end,
                    indentexpr = function() end,
                },
            }

            override.disable_core_indent(core_indent, render_buffer_fn, function() end)

            local buf = vim.api.nvim_create_buf(false, true)
            core_indent.public.reindent_range(buf, 0, 10)
            assert.equal(buf, called_with)
            vim.api.nvim_buf_delete(buf, { force = true })
        end)

        it("replaces buffer_set_line_indent with a no-op", function()
            local core_indent = {
                on_event = function() end,
                public = {
                    reindent_range = function() end,
                    buffer_set_line_indent = function()
                        return "original"
                    end,
                    indentexpr = function() end,
                },
            }

            override.disable_core_indent(core_indent, function() end, function() end)

            assert.is_nil(core_indent.public.buffer_set_line_indent())
        end)

        it("replaces public.indentexpr with custom function", function()
            local core_indent = {
                on_event = function() end,
                public = {
                    reindent_range = function() end,
                    buffer_set_line_indent = function() end,
                    indentexpr = function()
                        return -1
                    end,
                },
            }

            local indentexpr_fn = function()
                return 42
            end

            override.disable_core_indent(core_indent, function() end, indentexpr_fn)

            assert.equal(42, core_indent.public.indentexpr())
        end)

        it("skips reindent_range when buffer is invalid", function()
            local called = false
            local render_buffer_fn = function()
                called = true
            end

            local core_indent = {
                on_event = function() end,
                public = {
                    reindent_range = function() end,
                    buffer_set_line_indent = function() end,
                    indentexpr = function() end,
                },
            }

            override.disable_core_indent(core_indent, render_buffer_fn, function() end)

            -- Use an invalid buffer id
            core_indent.public.reindent_range(99999, 0, 10)
            assert.is_false(called)
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
