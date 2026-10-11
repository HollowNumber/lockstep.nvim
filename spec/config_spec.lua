describe("lockstep.config", function()
	local config
	local real_notify = vim.notify
	---@type string[]
	local notes

	before_each(function()
		package.loaded["lockstep.config"] = nil
		config = require("lockstep.config")
		notes = {}
		---@diagnostic disable-next-line: duplicate-set-field
		vim.notify = function(msg)
			table.insert(notes, msg)
		end
	end)

	after_each(function()
		vim.notify = real_notify
		vim.g.lockstep = nil
	end)

	describe("get", function()
		it("returns the defaults when vim.g.lockstep is unset", function()
			assert.are.same({ code_action = false, lsp_timeout_ms = 1000, project_scan = true }, config.get())
			assert.are.equal(0, #notes)
		end)

		it("overrides only the keys the user sets", function()
			vim.g.lockstep = { code_action = true }
			assert.are.same({ code_action = true, lsp_timeout_ms = 1000, project_scan = true }, config.get())
		end)

		it("keeps the default for an invalid value", function()
			vim.g.lockstep = { lsp_timeout_ms = "500", project_scan = false }
			local got = config.get()
			assert.are.equal(1000, got.lsp_timeout_ms)
			assert.is_false(got.project_scan)
		end)

		it("warns once about problems", function()
			vim.g.lockstep = { lsp_timeout_ms = -1, typo = true }
			config.get()
			config.get()
			assert.are.equal(1, #notes)
			assert.is_truthy(notes[1]:find("lsp_timeout_ms must be positive"))
			assert.is_truthy(notes[1]:find("unknown option: typo"))
		end)

		it("picks up changes to vim.g.lockstep", function()
			assert.is_false(config.get().code_action)
			vim.g.lockstep = { code_action = true }
			assert.is_true(config.get().code_action)
		end)

		it("returns a copy that can't change the defaults", function()
			config.get().lsp_timeout_ms = 1
			assert.are.equal(1000, config.get().lsp_timeout_ms)
		end)
	end)

	describe("setup", function()
		it("sets the options like vim.g.lockstep does", function()
			require("lockstep").setup({ code_action = true })
			assert.is_true(config.get().code_action)
		end)

		it("merges with an existing vim.g.lockstep", function()
			vim.g.lockstep = { project_scan = false }
			require("lockstep").setup({ code_action = true })
			local got = config.get()
			assert.is_true(got.code_action)
			assert.is_false(got.project_scan)
		end)

		it("accepts no arguments", function()
			require("lockstep").setup()
			assert.are.same({}, vim.g.lockstep)
			assert.is_false(config.get().code_action)
		end)
	end)

	describe("validate", function()
		it("accepts nil and a valid table", function()
			assert.are.same({}, config.validate(nil))
			assert.are.same({}, config.validate({ code_action = true, lsp_timeout_ms = 200 }))
		end)

		it("rejects a non-table", function()
			assert.are.same({ "vim.g.lockstep must be a table" }, config.validate(true))
		end)

		it("reports a wrong type", function()
			assert.are.same(
				{ "project_scan should be a boolean, got string" },
				config.validate({ project_scan = "no" })
			)
		end)

		it("reports an unknown option", function()
			assert.are.same({ "unknown option: code_actions" }, config.validate({ code_actions = true }))
		end)

		it("reports a non-positive timeout", function()
			assert.are.same({ "lsp_timeout_ms must be positive, got 0" }, config.validate({ lsp_timeout_ms = 0 }))
		end)
	end)
end)
