local MODREV, SPECREV = "scm", "-1"
rockspec_format = "3.0"
package = "neorg-indent"
version = MODREV .. SPECREV

description = {
    summary = "Neorg module for hierarchical indentation of norg files",
    labels = { "neovim" },
    homepage = "https://github.com/jeangnc/neorg-indent",
    license = "MIT",
}

source = {
    url = "https://github.com/jeangnc/neorg-indent/archive/v" .. MODREV .. ".zip",
}

if MODREV == "scm" then
    source = {
        url = "git://github.com/jeangnc/neorg-indent",
    }
end

dependencies = {
    "neorg ~> 9",
}

test_dependencies = {
    "busted",
    "nlua",
}

build = {
    type = "builtin",
    copy_directories = {},
}

test = {
    type = "busted",
}
