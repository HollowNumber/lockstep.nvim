local parse = require("lockstep.parse")
local edit = require("lockstep.edit")

---Scratch buffer with the given lines and filetype.
---@param lines string[]
---@param ft? string
---@return integer
local function make_buf(lines, ft)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].filetype = ft or "c"
	return buf
end

---@param buf integer
---@return string[]
local function lines_of(buf)
	return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

local DOC = "/// Adds two numbers."

describe("edit.apply", function()
	local source, header

	---The definition in `source` and the prototype in `header`.
	---@return lockstep.Site, lockstep.Site
	local function sites()
		local def = assert(parse.find_by_name(source, "add", "definition"))
		local decl = assert(parse.find_by_name(header, "add", "declaration"))
		return def, decl
	end

	before_each(function()
		source = make_buf({
			"static int add(int a, int b)",
			"{",
			"  return a + b;",
			"}",
		})
		header = make_buf({ DOC, "int add(int a, int b);" })
	end)

	after_each(function()
		vim.api.nvim_buf_delete(source, { force = true })
		vim.api.nvim_buf_delete(header, { force = true })
	end)

	it("copies a changed signature and returns changed", function()
		vim.api.nvim_buf_set_lines(source, 0, 1, false, { "static int add(int a, int b, int c)" })

		assert.are.equal("changed", edit.apply(sites()))
		assert.are.same({ DOC, "int add(int a, int b, int c);" }, lines_of(header))
	end)

	it("leaves the doc comment, the semicolon and static alone", function()
		vim.api.nvim_buf_set_lines(source, 0, 1, false, { "static int add(long a, long b)" })

		edit.apply(sites())
		local lines = lines_of(header)
		assert.are.equal(DOC, lines[1])
		assert.is_true(vim.endswith(lines[2], ";"))
		assert.is_nil(lines[2]:find("static"))
	end)

	it("returns unchanged and does not touch the buffer when they match", function()
		local tick = vim.b[header].changedtick

		assert.are.equal("unchanged", edit.apply(sites()))
		assert.are.equal(tick, vim.b[header].changedtick)
		assert.is_false(vim.bo[header].modified)
	end)

	it("replaces a single-line signature with a multi-line one", function()
		vim.api.nvim_buf_set_lines(source, 0, 1, false, { "int add(int a,", "        int b, int c)" })

		assert.are.equal("changed", edit.apply(sites()))
		assert.are.same({ DOC, "int add(int a,", "        int b, int c);" }, lines_of(header))
	end)

	it("replaces a multi-line signature with a single-line one", function()
		vim.api.nvim_buf_set_lines(header, 0, -1, false, { DOC, "int add(int a,", "        int b);" })
		vim.api.nvim_buf_set_lines(source, 0, 1, false, { "int add(int a, int b, int c)" })

		assert.are.equal("changed", edit.apply(sites()))
		assert.are.same({ DOC, "int add(int a, int b, int c);" }, lines_of(header))
	end)

	it("returns readonly for a non-modifiable target", function()
		vim.api.nvim_buf_set_lines(source, 0, 1, false, { "static int add(int a, int b, int c)" })
		local def, decl = sites()
		vim.bo[header].modifiable = false

		assert.are.equal("readonly", edit.apply(def, decl))
		assert.are.same({ DOC, "int add(int a, int b);" }, lines_of(header))
	end)

	it("returns stale when the source changed after building the site", function()
		vim.api.nvim_buf_set_lines(source, 0, 1, false, { "static int add(int a, int b, int c)" })
		local def, decl = sites()
		vim.api.nvim_buf_set_lines(source, -1, -1, false, { "" })

		assert.are.equal("stale", edit.apply(def, decl))
		assert.are.same({ DOC, "int add(int a, int b);" }, lines_of(header))
	end)

	it("returns stale when the target changed after building the site", function()
		vim.api.nvim_buf_set_lines(source, 0, 1, false, { "static int add(int a, int b, int c)" })
		local def, decl = sites()
		vim.api.nvim_buf_set_lines(header, 0, 0, false, { "" })

		assert.are.equal("stale", edit.apply(def, decl))
		assert.are.same({ "", DOC, "int add(int a, int b);" }, lines_of(header))
	end)

	it("errors on a site without a buffer", function()
		local def = sites()
		local from_text = assert(parse.find_by_name("int add(int a);", "add", "declaration", "c"))

		assert.has_error(function()
			edit.apply(def, from_text)
		end)
	end)
end)
