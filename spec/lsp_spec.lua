local lsp = require("lockstep.lsp")

local FIXTURES = vim.fs.normalize(vim.fn.fnamemodify("spec/fixtures", ":p"))

---@param rel string Path under spec/fixtures
---@return integer
local function open(rel)
	local buf = vim.fn.bufadd(FIXTURES .. "/" .. rel)
	vim.fn.bufload(buf)
	return buf
end

---Sends one request to a fresh server instance and waits for the reply.
---@param method string
---@param params table
---@return any
local function request(method, params)
	local server = lsp._server({
		notification = function() end,
		server_request = function() end,
		on_exit = function() end,
		on_error = function() end,
	})

	local done, result = false, nil
	server.request(method, params, function(_, res)
		done, result = true, res
	end)
	local finished = vim.wait(1000, function()
		return done
	end)
	assert(finished, "server never replied to " .. method)
	return result
end

---Code actions offered at a position.
---@param buf integer
---@param row integer
---@param col integer
---@return lsp.CodeAction[]
local function actions_at(buf, row, col)
	local pos = { line = row, character = col }
	return request("textDocument/codeAction", {
		textDocument = { uri = vim.uri_from_bufnr(buf) },
		range = { start = pos, ["end"] = pos },
		context = { diagnostics = {} },
	})
end

describe("lockstep.lsp", function()
	local real_notify = vim.notify

	before_each(function()
		---@diagnostic disable-next-line: duplicate-set-field
		vim.notify = function() end
	end)

	after_each(function()
		vim.notify = real_notify
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			vim.api.nvim_buf_delete(buf, { force = true })
		end
	end)

	it("advertises code actions in utf-8", function()
		local result = request("initialize", {})
		assert.is_true(result.capabilities.codeActionProvider)
		assert.are.equal("utf-8", result.capabilities.positionEncoding)
	end)

	it("offers sync on the signature line", function()
		local found = actions_at(open("pair/math.c"), 2, 4)
		assert.are.equal(1, #found)
		assert.are.equal("Sync signature to declaration", found[1].title)
		assert.are.equal(lsp.COMMAND, found[1].command.command)
	end)

	it("offers the other direction from a prototype", function()
		local found = actions_at(open("pair/math.h"), 4, 4)
		assert.are.equal("Sync signature to definition", found[1].title)
	end)

	it("offers nothing inside the function body", function()
		assert.are.same({}, actions_at(open("pair/math.c"), 4, 2))
	end)

	it("offers nothing outside a function", function()
		assert.are.same({}, actions_at(open("pair/math.c"), 0, 0))
	end)

	it("runs the sync when the command is executed", function()
		local c = open("pair/math.c")
		vim.api.nvim_buf_set_lines(c, 2, 3, false, { "int add(int a, int b, int c)" })
		local action = actions_at(c, 2, 4)[1]

		vim.lsp.commands[lsp.COMMAND](action.command, {})

		local h = open("pair/math.h")
		local updated = vim.wait(3000, function()
			return vim.api.nvim_buf_get_lines(h, 4, 5, false)[1] == "int add(int a, int b, int c);"
		end)
		assert.is_true(updated)
	end)

	it("does nothing when the function is gone by the time it runs", function()
		local c = open("pair/math.c")
		local action = actions_at(c, 2, 4)[1]
		vim.api.nvim_buf_set_lines(c, 0, -1, false, { "// nothing here" })

		assert.has_no.errors(function()
			vim.lsp.commands[lsp.COMMAND](action.command, {})
		end)
	end)
end)
