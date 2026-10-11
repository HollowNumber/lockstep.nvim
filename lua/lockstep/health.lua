local M = {}

local MIN_NVIM = "0.11"

function M.check()
	local health = vim.health

	health.start("Neovim")
	if vim.fn.has("nvim-" .. MIN_NVIM) == 1 then
		health.ok(("Neovim %s"):format(tostring(vim.version())))
	else
		health.error(("Neovim %s or newer is required"):format(MIN_NVIM))
	end

	health.start("Treesitter")
	local ok, added, err = pcall(vim.treesitter.language.add, "c")
	if ok and added then
		health.ok("C parser found")
	else
		health.error(
			"C parser not found: " .. tostring(err or added),
			{ "Neovim ships it; check that your runtime is intact or run `:TSInstall c`" }
		)
	end

	health.start("clangd (optional)")
	if vim.fn.executable("clangd") == 1 then
		health.ok("clangd found")
	else
		health.warn("clangd not found on PATH", {
			"lockstep still works without it, using Treesitter and file search",
			"with clangd, declarations in headers are found faster and more reliably",
		})
	end

	health.start("Configuration")
	local config = require("lockstep.config")
	local problems = config.validate(vim.g.lockstep)
	if #problems == 0 then
		health.ok(vim.g.lockstep == nil and "using defaults" or "vim.g.lockstep is valid")
	else
		for _, problem in ipairs(problems) do
			health.error(problem)
		end
	end
	local effective = config.get()
	health.info(
		("code_action: %s, lsp_timeout_ms: %d, project_scan: %s"):format(
			tostring(effective.code_action),
			effective.lsp_timeout_ms,
			tostring(effective.project_scan)
		)
	)
end

return M
