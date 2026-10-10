local lockstep = require("lockstep")

local FIXTURES = vim.fs.normalize(vim.fn.fnamemodify("spec/fixtures", ":p"))

---@param rel string Path under spec/fixtures
---@return integer
local function open(rel)
	local buf = vim.fn.bufadd(FIXTURES .. "/" .. rel)
	vim.fn.bufload(buf)
	return buf
end

---@param rel string
---@return string[]
local function lines_of(rel)
	return vim.api.nvim_buf_get_lines(open(rel), 0, -1, false)
end

---Runs lockstep.sync and waits for it to finish.
---@param buf integer
---@param row integer
---@param col integer
---@return lockstep.EditResult?
local function sync(buf, row, col)
	local done, result = false, nil
	lockstep.sync(buf, row, col, function(r)
		done, result = true, r
	end)
	local finished = vim.wait(3000, function()
		return done
	end)
	assert(finished, "lockstep.sync never finished")
	return result
end

describe("lockstep.sync", function()
	local real_notify = vim.notify
	---@type { msg: string, level: integer? }[]
	local notes

	before_each(function()
		notes = {}
		---@diagnostic disable-next-line: duplicate-set-field
		vim.notify = function(msg, level)
			table.insert(notes, { msg = msg, level = level })
		end
	end)

	after_each(function()
		vim.notify = real_notify
		-- Buffers are edited but never written, so the fixture files stay as they are
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			vim.api.nvim_buf_delete(buf, { force = true })
		end
	end)

	it("updates the declaration from the definition", function()
		local c = open("pair/math.c")
		vim.api.nvim_buf_set_lines(c, 2, 3, false, { "int add(int a, int b, int c)" })

		assert.are.equal("changed", sync(c, 4, 2))
		assert.are.equal("int add(int a, int b, int c);", lines_of("pair/math.h")[5])
		assert.is_truthy(notes[1].msg:find("Updated declaration of add%(%) in math.h"))
	end)

	it("updates the definition from the declaration", function()
		local h = open("pair/math.h")
		vim.api.nvim_buf_set_lines(h, 4, 5, false, { "int add(long a, long b);" })

		assert.are.equal("changed", sync(h, 4, 4))
		assert.are.equal("int add(long a, long b)", lines_of("pair/math.c")[3])
	end)

	it("reports when both sides already match", function()
		assert.are.equal("unchanged", sync(open("pair/math.c"), 4, 2))
		assert.is_truthy(notes[1].msg:find("already in sync"))
	end)

	it("warns when there is no other side", function()
		assert.is_nil(sync(open("static_proto/one.c"), 4, 2))
		assert.are.equal(vim.log.levels.WARN, notes[1].level)
		assert.is_truthy(notes[1].msg:find("No declaration found for run%(%)"))
	end)

	it("warns when the cursor isn't on a function", function()
		assert.is_nil(sync(open("pair/math.c"), 0, 0))
		assert.are.equal(vim.log.levels.WARN, notes[1].level)
	end)
end)
