rockspec_format = "3.0"
package = "lockstep.nvim"
version = "scm-1"
source = {
	url = "git+https://github.com/HollowNumber/lockstep.nvim",
}
dependencies = {}
test_dependencies = {
	"nlua",
}
build = {
	type = "builtin",
	copy_directories = {
		"plugin",
		"queries",
		"doc",
	},
}

description = {
	homepage = "https://github.com/HollowNumber/lockstep.nvim",
	summary = "Keep C declarations and definitions in lockstep: live signature sync, header/source scaffolding, and a split view",
	license = "MIT",
	labels = { "neovim", "neovim-plugin", "c" },
}
