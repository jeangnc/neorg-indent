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

--- Full-pipeline helper: parse norg content, compute indent info, and return desired indent.
---@param norg_content string norg source text
---@param row number 0-based row
---@param config table indent configuration
---@return number desired indent in spaces
local function desired_indent(norg_content, row, config)
    local root, buf = parse_norg(norg_content)
    local info = calculation.indent_level_for_row(root, row, buf)
    local result = calculation.desired_indent_for_info(info, config)
    cleanup_buf(buf)
    return result
end

describe("external.indent", function()
    describe("indent calculation", function()
        describe("with default config (indent_per_level only)", function()
            local config = { indent_per_level = 4 }

            it("does not indent heading prefix lines", function()
                assert.equal(0, desired_indent("* Heading 1", 0, config))
                assert.equal(0, desired_indent("* H1\n** H2\n*** H3", 0, config))
            end)

            it("indents h2 prefix under h1 by one level", function()
                assert.equal(4, desired_indent("* H1\n** H2", 1, config))
            end)

            it("indents h3 prefix under h1/h2 by two levels", function()
                assert.equal(8, desired_indent("* H1\n** H2\n*** H3", 2, config))
            end)

            it("indents content under h1 by one level plus conceal compensation", function()
                -- 1 heading contribution (h1=4) + conceal_compensation(1) = 5
                assert.equal(5, desired_indent("* H1\nContent", 1, config))
            end)

            it("indents content under h2 by two levels plus conceal compensation", function()
                -- 2 heading contributions (h1=4, h2=4) + conceal_compensation(2) = 10
                assert.equal(10, desired_indent("* H1\n** H2\nContent", 2, config))
            end)

            it("indents content under h3 by three levels plus conceal compensation", function()
                -- 3 heading contributions (h1=4, h2=4, h3=4) + conceal_compensation(3) = 15
                assert.equal(15, desired_indent("* H1\n** H2\n*** H3\nContent", 3, config))
            end)

            it("indents content under h4 by four levels plus conceal compensation", function()
                -- 4 heading contributions (4*4) + conceal_compensation(4) = 20
                assert.equal(20, desired_indent("* H1\n** H2\n*** H3\n**** H4\nContent", 4, config))
            end)

            it("indents list item under heading by heading levels", function()
                -- h1 + h2 contributions (4+4) + conceal_compensation(2) = 10
                assert.equal(10, desired_indent("* H1\n** H2\n- List item", 2, config))
            end)

            it("indents nested list by heading levels plus list nesting", function()
                -- h1 + h2 (4+4) + list_nesting 1 (4) + conceal_compensation(2) = 14
                assert.equal(14, desired_indent("* H1\n** H2\n- Item\n-- Nested", 3, config))
            end)

            it("indents empty line under heading", function()
                -- empty line between h1 and h2 is under h1
                assert.equal(5, desired_indent("* H1\n\n** H2", 1, config))
            end)
        end)

        describe("with heading_indent for all levels", function()
            local config = {
                indent_per_level = 4,
                heading_indent = { [1] = 2, [2] = 3, [3] = 5, [4] = 1 },
            }

            it("uses configured heading indent for h1 content without conceal", function()
                -- heading_indent[1]=2, conceal suppressed because heading_indent[1] exists
                assert.equal(2, desired_indent("* H1\nContent", 1, config))
            end)

            it("uses configured heading indent for h2 content without conceal", function()
                -- heading_indent[1]=2 + heading_indent[2]=3 = 5, conceal suppressed
                assert.equal(5, desired_indent("* H1\n** H2\nContent", 2, config))
            end)

            it("uses configured heading indent for h3 content without conceal", function()
                -- 2 + 3 + 5 = 10, conceal suppressed
                assert.equal(10, desired_indent("* H1\n** H2\n*** H3\nContent", 3, config))
            end)

            it("uses configured heading indent for h4 content without conceal", function()
                -- 2 + 3 + 5 + 1 = 11, conceal suppressed
                assert.equal(11, desired_indent("* H1\n** H2\n*** H3\n**** H4\nContent", 4, config))
            end)

            it("uses configured heading indent for heading prefix lines", function()
                -- h2 prefix under h1 → heading_indent[1] = 2
                assert.equal(2, desired_indent("* H1\n** H2", 1, config))
                -- h3 prefix under h1/h2 → heading_indent[1] + heading_indent[2] = 5
                assert.equal(5, desired_indent("* H1\n** H2\n*** H3", 2, config))
            end)
        end)

        describe("with heading_indent for some levels (per-level conceal suppression)", function()
            local config = {
                indent_per_level = 2,
                heading_indent = { [1] = 0 },
            }

            it("produces 0 indent for h1 content when heading_indent[1] is 0", function()
                -- heading_indent[1]=0, conceal suppressed for level 1 → 0
                assert.equal(0, desired_indent("* H1\nContent", 1, config))
            end)

            it("preserves conceal for levels falling back to indent_per_level", function()
                -- heading_indent[1]=0 + indent_per_level=2 for h2
                -- conceal_compensation=2 (innermost is h2, no heading_indent[2])
                -- total = 0 + 2 + 2 = 4
                assert.equal(4, desired_indent("* H1\n** H2\nContent", 2, config))
            end)

            it("preserves conceal for h3 falling back to indent_per_level", function()
                -- heading_indent[1]=0 + indent_per_level=2 + indent_per_level=2
                -- conceal_compensation=3 (innermost is h3, no heading_indent[3])
                -- total = 0 + 2 + 2 + 3 = 7
                assert.equal(7, desired_indent("* H1\n** H2\n*** H3\nContent", 3, config))
            end)

            it("preserves conceal for h4 falling back to indent_per_level", function()
                -- heading_indent[1]=0 + indent_per_level=2 * 3
                -- conceal_compensation=4 (innermost is h4, no heading_indent[4])
                -- total = 0 + 2 + 2 + 2 + 4 = 10
                assert.equal(10, desired_indent("* H1\n** H2\n*** H3\n**** H4\nContent", 4, config))
            end)

            it("suppresses conceal only for h1 prefix lines too", function()
                -- h2 prefix under h1: heading_indent[1]=0, no conceal on prefix
                assert.equal(0, desired_indent("* H1\n** H2", 1, config))
            end)
        end)

        describe("continuation lines", function()
            local config = { indent_per_level = 4 }

            it("adds continuation indent for second line of list item", function()
                local indent = desired_indent("- List item\n  continued", 1, config)
                -- continuation_indent = 2 (aligns after "- ")
                assert.equal(2, indent)
            end)

            it("does not add continuation indent for list prefix line", function()
                assert.equal(0, desired_indent("- List item", 0, config))
            end)

            it("combines heading indent and continuation indent", function()
                local indent = desired_indent("* H1\n- List item\n  continued", 2, config)
                -- h1 contribution (4) + conceal_compensation(1) + continuation_indent(2) = 7
                assert.equal(7, indent)
            end)
        end)

        describe("pre-indented content", function()
            local config = { indent_per_level = 4 }

            it("computes correct indent for pre-indented content under h2", function()
                assert.equal(10, desired_indent("* H1\n    ** H2\n        Content", 2, config))
            end)

            it("computes correct indent for pre-indented nested list", function()
                local indent = desired_indent("* H1\n    ** H2\n        - Item\n            -- Nested", 3, config)
                -- h1(4) + h2(4) + list_nesting 1 (4) + conceal_compensation(2) = 14
                assert.equal(14, indent)
            end)
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

end)
