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

local CONFIG = { indent_per_level = 4 }

describe("external.indent", function()
    describe("indent_level_for_row (pre-indented content)", function()
        it("returns heading_contributions {1,2} and list_nesting 0 for pre-indented list under heading2", function()
            local root, buf = parse_norg("* Heading 1\n    ** Heading 2\n        - List item")
            local info = calculation.indent_level_for_row(root, 2, buf)

            assert.same({ 1, 2 }, info.heading_contributions)
            assert.equal(0, info.list_nesting)

            cleanup_buf(buf)
        end)

        it("returns heading_contributions {1,2} and list_nesting 1 for pre-indented nested list item", function()
            local root, buf =
                parse_norg("* Heading 1\n    ** Heading 2\n        - List item\n            -- Nested item")
            local info = calculation.indent_level_for_row(root, 3, buf)

            assert.same({ 1, 2 }, info.heading_contributions)
            assert.equal(1, info.list_nesting)

            cleanup_buf(buf)
        end)

        it("returns heading_contributions {1,2} for pre-indented content under heading2", function()
            local root, buf = parse_norg("* Heading 1\n    ** Heading 2\n        Content under h2")
            local info = calculation.indent_level_for_row(root, 2, buf)

            assert.same({ 1, 2 }, info.heading_contributions)
            assert.equal(0, info.list_nesting)

            cleanup_buf(buf)
        end)

        it("returns heading_contributions {1,2} for pre-indented heading3 prefix under heading2", function()
            local root, buf = parse_norg("* Heading 1\n    ** Heading 2\n        *** Heading 3")
            local info = calculation.indent_level_for_row(root, 2, buf)

            assert.same({ 1, 2 }, info.heading_contributions)
            assert.equal(0, info.list_nesting)

            cleanup_buf(buf)
        end)

        it("returns heading_contributions {1,2,3} for pre-indented content under heading3", function()
            local root, buf =
                parse_norg("* Heading 1\n    ** Heading 2\n        *** Heading 3\n            Content under h3")
            local info = calculation.indent_level_for_row(root, 3, buf)

            assert.same({ 1, 2, 3 }, info.heading_contributions)
            assert.equal(0, info.list_nesting)

            cleanup_buf(buf)
        end)

        it("returns heading_contributions {1,2,3} for pre-indented heading4 prefix under heading3", function()
            local root, buf =
                parse_norg("* Heading 1\n    ** Heading 2\n        *** Heading 3\n            **** Heading 4")
            local info = calculation.indent_level_for_row(root, 3, buf)

            assert.same({ 1, 2, 3 }, info.heading_contributions)
            assert.equal(0, info.list_nesting)

            cleanup_buf(buf)
        end)

        it("returns heading_contributions {1,2,3,4} for pre-indented content under heading4", function()
            local content =
                "* Heading 1\n    ** Heading 2\n        *** Heading 3\n            **** Heading 4\n                Content under h4"
            local root, buf = parse_norg(content)
            local info = calculation.indent_level_for_row(root, 4, buf)

            assert.same({ 1, 2, 3, 4 }, info.heading_contributions)
            assert.equal(0, info.list_nesting)

            cleanup_buf(buf)
        end)

        it("returns heading_contributions {1,2,3,4} and list_nesting 0 for pre-indented list item under heading4", function()
            local content =
                "* Heading 1\n    ** Heading 2\n        *** Heading 3\n            **** Heading 4\n                - List item"
            local root, buf = parse_norg(content)
            local info = calculation.indent_level_for_row(root, 4, buf)

            assert.same({ 1, 2, 3, 4 }, info.heading_contributions)
            assert.equal(0, info.list_nesting)

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
        it("returns empty heading_contributions for heading1 prefix line", function()
            local root, buf = parse_norg("* Heading 1")
            local info = calculation.indent_level_for_row(root, 0, buf)

            assert.same({}, info.heading_contributions)
            assert.equal(0, info.list_nesting)

            cleanup_buf(buf)
        end)

        it("returns heading_contributions {1} for content under heading1", function()
            local root, buf = parse_norg("* Heading 1\nSome content")
            local info = calculation.indent_level_for_row(root, 1, buf)

            assert.same({ 1 }, info.heading_contributions)
            assert.equal(0, info.list_nesting)

            cleanup_buf(buf)
        end)

        it("returns heading_contributions {1} for heading2 prefix under heading1", function()
            local root, buf = parse_norg("* Heading 1\n** Heading 2")
            local info = calculation.indent_level_for_row(root, 1, buf)

            assert.same({ 1 }, info.heading_contributions)
            assert.equal(0, info.list_nesting)

            cleanup_buf(buf)
        end)

        it("returns heading_contributions {1,2} for content under heading2", function()
            local root, buf = parse_norg("* Heading 1\n** Heading 2\nContent under h2")
            local info = calculation.indent_level_for_row(root, 2, buf)

            assert.same({ 1, 2 }, info.heading_contributions)
            assert.equal(0, info.list_nesting)

            cleanup_buf(buf)
        end)

        it("returns heading_contributions {1,2} and list_nesting 0 for list item under heading2", function()
            local root, buf = parse_norg("* Heading 1\n** Heading 2\n- List item")
            local info = calculation.indent_level_for_row(root, 2, buf)

            assert.same({ 1, 2 }, info.heading_contributions)
            assert.equal(0, info.list_nesting)

            cleanup_buf(buf)
        end)

        it("returns heading_contributions {1,2} and list_nesting 1 for nested list item", function()
            local root, buf = parse_norg("* Heading 1\n** Heading 2\n- List item\n-- Nested item")
            local info = calculation.indent_level_for_row(root, 3, buf)

            assert.same({ 1, 2 }, info.heading_contributions)
            assert.equal(1, info.list_nesting)

            cleanup_buf(buf)
        end)

        it("returns heading_contributions {1,2} for heading3 prefix under heading2", function()
            local root, buf = parse_norg("* Heading 1\n** Heading 2\n*** Heading 3")
            local info = calculation.indent_level_for_row(root, 2, buf)

            assert.same({ 1, 2 }, info.heading_contributions)
            assert.equal(0, info.list_nesting)

            cleanup_buf(buf)
        end)

        it("returns heading_contributions {1,2,3} for content under heading3", function()
            local root, buf = parse_norg("* Heading 1\n** Heading 2\n*** Heading 3\nContent under h3")
            local info = calculation.indent_level_for_row(root, 3, buf)

            assert.same({ 1, 2, 3 }, info.heading_contributions)
            assert.equal(0, info.list_nesting)

            cleanup_buf(buf)
        end)

        it("returns heading_contributions {1,2,3} for heading4 prefix under heading3", function()
            local root, buf = parse_norg("* Heading 1\n** Heading 2\n*** Heading 3\n**** Heading 4")
            local info = calculation.indent_level_for_row(root, 3, buf)

            assert.same({ 1, 2, 3 }, info.heading_contributions)
            assert.equal(0, info.list_nesting)

            cleanup_buf(buf)
        end)

        it("returns heading_contributions {1,2,3,4} for content under heading4", function()
            local content = "* Heading 1\n** Heading 2\n*** Heading 3\n**** Heading 4\nContent under h4"
            local root, buf = parse_norg(content)
            local info = calculation.indent_level_for_row(root, 4, buf)

            assert.same({ 1, 2, 3, 4 }, info.heading_contributions)
            assert.equal(0, info.list_nesting)

            cleanup_buf(buf)
        end)

        it("returns heading_contributions {1,2,3,4} and list_nesting 0 for list item under heading4", function()
            local root, buf = parse_norg("* Heading 1\n** Heading 2\n*** Heading 3\n**** Heading 4\n- List item")
            local info = calculation.indent_level_for_row(root, 4, buf)

            assert.same({ 1, 2, 3, 4 }, info.heading_contributions)
            assert.equal(0, info.list_nesting)

            cleanup_buf(buf)
        end)

        it("inherits parent heading level for empty line between headings", function()
            local root, buf = parse_norg("* Heading 1\n\n** Heading 2")
            local info = calculation.indent_level_for_row(root, 1, buf)

            assert.same({ 1 }, info.heading_contributions)
            assert.equal(0, info.list_nesting)

            cleanup_buf(buf)
        end)

        it("returns continuation_indent 0 for non-list lines", function()
            local root, buf = parse_norg("* Heading 1\nSome content")
            local info = calculation.indent_level_for_row(root, 1, buf)

            assert.equal(0, info.continuation_indent)

            cleanup_buf(buf)
        end)

        it("returns same indent structure for list item and sibling paragraph under heading", function()
            local root, buf = parse_norg("* Heading 1\nParagraph text\n- List item")
            local para_info = calculation.indent_level_for_row(root, 1, buf)
            local list_info = calculation.indent_level_for_row(root, 2, buf)

            assert.same(para_info.heading_contributions, list_info.heading_contributions)
            assert.equal(para_info.list_nesting, list_info.list_nesting)

            cleanup_buf(buf)
        end)

        it("returns heading_contributions {1} and list_nesting 0 for list1 item after blank line", function()
            local root, buf = parse_norg("* Heading 1\n- Item 1\n\n- Item 2")
            local info = calculation.indent_level_for_row(root, 3, buf)

            assert.same({ 1 }, info.heading_contributions)
            assert.equal(0, info.list_nesting)

            cleanup_buf(buf)
        end)

        it("returns heading_contributions {1} and list_nesting 1 for list2 item after blank line", function()
            local root, buf = parse_norg("* Heading 1\n- Item 1\n-- Sub 1\n\n-- Sub 2")
            local info = calculation.indent_level_for_row(root, 4, buf)

            assert.same({ 1 }, info.heading_contributions)
            assert.equal(1, info.list_nesting)

            cleanup_buf(buf)
        end)

        it("returns heading_contributions {1} and list_nesting 2 for list3 item after blank line", function()
            local root, buf = parse_norg("* Heading 1\n- Item 1\n-- Sub 1\n--- SubSub 1\n\n--- SubSub 2")
            local info = calculation.indent_level_for_row(root, 5, buf)

            assert.same({ 1 }, info.heading_contributions)
            assert.equal(2, info.list_nesting)

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
        it("computes correct indent after promote (h2 → h3)", function()
            -- Simulates core.promo promoting h2 to h3: the *** prefix is in place
            -- but whitespace still reflects the old h2 level (4 spaces).
            local root, buf = parse_norg("* Heading 1\n    *** Heading 3\n        Content under h3")
            local h3_info = calculation.indent_level_for_row(root, 1, buf)
            local content_info = calculation.indent_level_for_row(root, 2, buf)

            -- h3 prefix under h1 → heading_contributions {1}
            assert.same({ 1 }, h3_info.heading_contributions)
            -- Content under h3 → heading_contributions {1, 3}
            assert.same({ 1, 3 }, content_info.heading_contributions)

            cleanup_buf(buf)
        end)

        it("computes correct indent after demote (h2 → h1)", function()
            -- Simulates core.promo demoting h2 to h1: the * prefix is in place
            -- but whitespace still reflects the old h2 level (4 spaces).
            local root, buf = parse_norg("    * Heading 1\n        Content under h1")
            local h1_info = calculation.indent_level_for_row(root, 0, buf)
            local content_info = calculation.indent_level_for_row(root, 1, buf)

            -- h1 prefix → heading_contributions {}
            assert.same({}, h1_info.heading_contributions)
            -- Content under h1 → heading_contributions {1}
            assert.same({ 1 }, content_info.heading_contributions)

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
            renderer.apply_indent(buf, 0, line_count, indent_map, CONFIG)

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
            renderer.apply_indent(buf, 0, line_count, indent_map, CONFIG)

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

        it("redirects reindent_range to render_buffer_fn", function()
            local called_with = nil
            local render_buffer_fn = function(buffer)
                called_with = buffer
            end

            local public = {
                reindent_range = function() end,
                buffer_set_line_indent = function() end,
                indentexpr = function() end,
            }

            override.disable_core_indent(public, render_buffer_fn, function() end)

            local buf = vim.api.nvim_create_buf(false, true)
            public.reindent_range(buf, 0, 10)
            assert.equal(buf, called_with)
            vim.api.nvim_buf_delete(buf, { force = true })
        end)

        it("replaces buffer_set_line_indent with a no-op", function()
            local public = {
                reindent_range = function() end,
                buffer_set_line_indent = function()
                    return "original"
                end,
                indentexpr = function() end,
            }

            override.disable_core_indent(public, function() end, function() end)

            assert.is_nil(public.buffer_set_line_indent())
        end)

        it("replaces indentexpr with custom function", function()
            local public = {
                reindent_range = function() end,
                buffer_set_line_indent = function() end,
                indentexpr = function()
                    return -1
                end,
            }

            local indentexpr_fn = function()
                return 42
            end

            override.disable_core_indent(public, function() end, indentexpr_fn)

            assert.equal(42, public.indentexpr())
        end)

        it("skips reindent_range when buffer is invalid", function()
            local called = false
            local render_buffer_fn = function()
                called = true
            end

            local public = {
                reindent_range = function() end,
                buffer_set_line_indent = function() end,
                indentexpr = function() end,
            }

            override.disable_core_indent(public, render_buffer_fn, function() end)

            -- Use an invalid buffer id
            public.reindent_range(99999, 0, 10)
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
                [1] = { heading_contributions = { 1 }, list_nesting = 0, continuation_indent = 0 },
            }

            renderer.apply_indent(buf, 0, 2, indent_map, CONFIG)

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

            renderer.apply_indent(buf, 0, 1, {}, CONFIG)

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
                [0] = { heading_contributions = { 1, 2 }, list_nesting = 0, continuation_indent = 0 },
            }

            renderer.apply_indent(buf, 0, 1, indent_map, CONFIG)

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
                [0] = { heading_contributions = { 1 }, list_nesting = 0, continuation_indent = 2 },
            }

            renderer.apply_indent(buf, 0, 1, indent_map, CONFIG)

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
                [0] = { heading_contributions = { 1 }, list_nesting = 0, continuation_indent = 0 },
            }

            renderer.apply_indent(buf, 0, 1, indent_map, CONFIG, { preserve_modified = true })

            assert.is_false(vim.bo[buf].modified)

            vim.api.nvim_buf_delete(buf, { force = true })
        end)
    end)

    describe("per-level indent spacing", function()
        it("uses heading_indent config for different heading levels", function()
            local info = {
                heading_contributions = { 1, 2, 3 },
                list_nesting = 0,
                continuation_indent = 0,
                conceal_compensation = 0,
            }
            local config = {
                indent_per_level = 4,
                heading_indent = { [1] = 2, [2] = 3, [3] = 5 },
            }

            local result = calculation.desired_indent_for_info(info, config)
            -- 2 + 3 + 5 = 10
            assert.equal(10, result)
        end)

        it("uses list_indent config for different list nesting levels", function()
            local info = {
                heading_contributions = {},
                list_nesting = 3,
                continuation_indent = 0,
                conceal_compensation = 0,
            }
            local config = {
                indent_per_level = 4,
                list_indent = { [1] = 2, [2] = 3, [3] = 6 },
            }

            local result = calculation.desired_indent_for_info(info, config)
            -- 2 + 3 + 6 = 11
            assert.equal(11, result)
        end)

        it("falls back to indent_per_level for missing heading_indent entries", function()
            local info = {
                heading_contributions = { 1, 2, 3 },
                list_nesting = 0,
                continuation_indent = 0,
                conceal_compensation = 0,
            }
            local config = {
                indent_per_level = 4,
                heading_indent = { [1] = 2 }, -- only h1 specified
            }

            local result = calculation.desired_indent_for_info(info, config)
            -- 2 + 4 + 4 = 10
            assert.equal(10, result)
        end)

        it("falls back to indent_per_level for missing list_indent entries", function()
            local info = {
                heading_contributions = {},
                list_nesting = 3,
                continuation_indent = 0,
                conceal_compensation = 0,
            }
            local config = {
                indent_per_level = 4,
                list_indent = { [1] = 2 }, -- only depth 1 specified
            }

            local result = calculation.desired_indent_for_info(info, config)
            -- 2 + 4 + 4 = 10
            assert.equal(10, result)
        end)

        it("falls back to indent_per_level when heading_indent is nil", function()
            local info = {
                heading_contributions = { 1, 2 },
                list_nesting = 0,
                continuation_indent = 0,
                conceal_compensation = 0,
            }
            local config = {
                indent_per_level = 4,
            }

            local result = calculation.desired_indent_for_info(info, config)
            -- 4 + 4 = 8
            assert.equal(8, result)
        end)

        it("combines heading and list per-level indent", function()
            local info = {
                heading_contributions = { 1, 2 },
                list_nesting = 2,
                continuation_indent = 0,
                conceal_compensation = 0,
            }
            local config = {
                indent_per_level = 4,
                heading_indent = { [1] = 2, [2] = 3 },
                list_indent = { [1] = 1, [2] = 2 },
            }

            local result = calculation.desired_indent_for_info(info, config)
            -- heading: 2 + 3 = 5, list: 1 + 2 = 3, total = 8
            assert.equal(8, result)
        end)

        it("includes continuation_indent and conceal_compensation with per-level indent", function()
            local info = {
                heading_contributions = { 1 },
                list_nesting = 1,
                continuation_indent = 3,
                conceal_compensation = 2,
            }
            local config = {
                indent_per_level = 4,
                heading_indent = { [1] = 6 },
                list_indent = { [1] = 2 },
            }

            local result = calculation.desired_indent_for_info(info, config)
            -- heading: 6, list: 2, continuation: 3, conceal: 2, total = 13
            assert.equal(13, result)
        end)

        it("renders buffer correctly with per-level heading indent", function()
            local buf = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_lines(buf, 0, -1, true, {
                "* Heading 1",
                "Content under h1",
                "** Heading 2",
                "Content under h2",
            })

            local indent_map = {
                [1] = { heading_contributions = { 1 }, list_nesting = 0, continuation_indent = 0, conceal_compensation = 0 },
                [2] = { heading_contributions = { 1 }, list_nesting = 0, continuation_indent = 0, conceal_compensation = 0 },
                [3] = { heading_contributions = { 1, 2 }, list_nesting = 0, continuation_indent = 0, conceal_compensation = 0 },
            }

            local config = {
                indent_per_level = 4,
                heading_indent = { [1] = 2, [2] = 6 },
            }

            renderer.apply_indent(buf, 0, 4, indent_map, config)

            local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, true)
            assert.equal("* Heading 1", lines[1])
            -- h1 contributes 2 spaces
            assert.equal("  Content under h1", lines[2])
            -- h2 prefix under h1 → h1 contributes 2 spaces
            assert.equal("  ** Heading 2", lines[3])
            -- Content under h2 → h1(2) + h2(6) = 8 spaces
            assert.equal("        Content under h2", lines[4])

            vim.api.nvim_buf_delete(buf, { force = true })
        end)
    end)
end)
