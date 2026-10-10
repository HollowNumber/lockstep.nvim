local parse = require("lockstep.parse")

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

local SOURCE = {
	'#include "a.h"', -- 0
	"static int helper(int x);", -- 1
	"int counter;", -- 2
	"__attribute__((unused)) static inline int", -- 3
	"add(int a,", -- 4
	"    int b)", -- 5
	"{", -- 6
	"  return a + b;", -- 7
	"}", -- 8
	"char *name(void) { return 0; }", -- 9
}

local HEADER = table.concat({
	"int add(int a, int b);",
	"int counter;",
	"char *name(void);",
}, "\n")

describe("parse.site_at", function()
	local buf

	before_each(function()
		buf = make_buf(SOURCE)
	end)

	after_each(function()
		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	it("finds the definition from inside its body", function()
		local site = assert(parse.site_at(buf, 7, 4))
		assert.are.equal("add", site.name)
		assert.are.equal("definition", site.kind)
		assert.are.equal("c", site.lang)
		assert.are.equal(buf, site.buf)
		assert.are.equal(4, site.name_pos.row)
		assert.are.equal(0, site.name_pos.col)
		assert.is_nil(site.path)
	end)

	it("starts the range after attributes, static and inline", function()
		local site = assert(parse.site_at(buf, 7, 4))
		assert.are.equal(3, site.range.start_row)
		assert.are.equal(38, site.range.start_col) -- the `int`
	end)

	it("ends the range after a multi-line parameter list", function()
		local site = assert(parse.site_at(buf, 7, 4))
		assert.are.same({ 5, 10 }, { site.range.end_row, site.range.end_col })
	end)

	it("treats a static prototype as a declaration", function()
		local site = assert(parse.site_at(buf, 1, 12))
		assert.are.equal("helper", site.name)
		assert.are.equal("declaration", site.kind)
		assert.are.equal(7, site.range.start_col) -- `static ` excluded
	end)

	it("handles pointer return types", function()
		local site = assert(parse.site_at(buf, 9, 8))
		assert.are.equal("name", site.name)
	end)

	it("returns nil on a variable declaration", function()
		assert.is_nil(parse.site_at(buf, 2, 5))
	end)
end)

describe("parse.find_by_name", function()
	it("finds a declaration in a string source", function()
		local site = assert(parse.find_by_name(HEADER, "add", "declaration", "cpp", "/x/a.h"))
		assert.are.equal("add", site.name)
		assert.are.equal(0, site.range.start_row)
		assert.are.equal("/x/a.h", site.path)
		assert.is_nil(site.buf)
	end)

	it("skips a variable with the same name", function()
		assert.is_nil(parse.find_by_name(HEADER, "counter", "declaration", "c"))
	end)

	it("returns nil for the wrong kind", function()
		assert.is_nil(parse.find_by_name(HEADER, "add", "definition", "c"))
	end)

	it("needs a language for string sources", function()
		assert.is_nil(parse.find_by_name(HEADER, "add", "declaration"))
	end)

	it("gives the same site for a buffer and a string", function()
		local buf = make_buf(SOURCE)
		local from_buf = assert(parse.find_by_name(buf, "add", "definition"))
		local from_str = assert(parse.find_by_name(table.concat(SOURCE, "\n"), "add", "definition", "c"))
		assert.are.same(from_buf.range, from_str.range)
		assert.are.equal(from_buf.name, from_str.name)
		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	it("falls back to the C parser for a header detected as C++", function()
		local buf = make_buf(vim.split(HEADER, "\n"), "cpp")
		local site = assert(parse.find_by_name(buf, "add", "declaration", "c"))
		assert.are.equal("cpp", site.lang)
		vim.api.nvim_buf_delete(buf, { force = true })
	end)
end)

describe("parse with half-typed code", function()
	it("returns nil for an unclosed parameter list instead of throwing", function()
		local buf = make_buf({ "int add(int a, ", "{", "  return a;", "}" })
		local ok, site = pcall(parse.site_at, buf, 0, 5)
		assert.is_true(ok)
		assert.is_nil(site)
		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	it("does not throw on a broken string source", function()
		assert.has_no.errors(function()
			parse.find_by_name("int add(int a,", "add", "declaration", "c")
		end)
	end)
end)
