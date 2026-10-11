local locate = require("lockstep.locate")
local parse = require("lockstep.parse")

local FIXTURES = vim.fs.normalize(vim.fn.fnamemodify("spec/fixtures", ":p"))

-- Index into locate.strategies, so tests can run one strategy at a time
local CLANGD, SAME_FILE, SWITCH, INCLUDES, OPEN_BUFFERS = 1, 2, 3, 4, 5

---Loads a fixture file into a buffer.
---@param rel string Path under spec/fixtures
---@return integer
local function open(rel)
	local buf = vim.fn.bufadd(FIXTURES .. "/" .. rel)
	vim.fn.bufload(buf)
	return buf
end

---The site at a position in a fixture file.
---@param rel string
---@param row integer
---@param col integer
---@return lockstep.Site
local function site_in(rel, row, col)
	local site = assert(parse.site_at(open(rel), row, col))
	return site
end

---Runs locate.find and waits for its callback.
---@param source lockstep.Site
---@param strategies? lockstep.Strategy[]
---@return lockstep.Site?
local function find(source, strategies)
	local done, result = false, nil
	locate.find(source, function(target)
		done, result = true, target
	end, strategies)
	assert(
		vim.wait(3000, function()
			return done
		end),
		"locate.find never called back"
	)
	return result
end

---@param site lockstep.Site?
---@return string
local function file_of(site)
	local buf = assert(site and site.buf)
	return vim.fs.basename(vim.api.nvim_buf_get_name(buf))
end

local function wipe_buffers()
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		vim.api.nvim_buf_delete(buf, { force = true })
	end

	vim.g.lockstep = nil
end

describe("locate.find without clangd", function()
	after_each(wipe_buffers)

	it("finds a static prototype in the same file", function()
		local target = find(site_in("static_proto/one.c", 9, 2))
		assert.are.equal("declaration", assert(target).kind)
		assert.are.equal(0, target.range.start_row)
	end)

	it("finds the definition from a static prototype", function()
		local target = find(site_in("static_proto/one.c", 0, 12))
		assert.are.equal("definition", assert(target).kind)
		assert.are.equal(7, target.range.start_row)
	end)

	it("finds the declaration through an include", function()
		local target = find(site_in("pair/math.c", 4, 2))
		assert.are.equal("math.h", file_of(target))
		assert.are.equal(4, assert(target).range.start_row)
	end)

	it("finds a header in <root>/include", function()
		local target = find(site_in("renamed/src/impl.c", 4, 2))
		assert.are.equal("api.h", file_of(target))
	end)

	it("finds the definition from a header by scanning the project", function()
		local target = find(site_in("pair/math.h", 4, 4))
		assert.are.equal("math.c", file_of(target))
		assert.are.equal("definition", assert(target).kind)
	end)

	it("searches buffers that are already open", function()
		open("pair/math.c")
		local target = find(site_in("pair/math.h", 4, 4), { locate.strategies[OPEN_BUFFERS] })
		assert.are.equal("math.c", file_of(target))
	end)

	it("skips build directories when scanning", function()
		local target = find(site_in("scan/main.c", 2, 2))
		local buf = assert(target and target.buf)
		local path = vim.api.nvim_buf_get_name(buf)
		assert.is_truthy(path:find("/lib/deep.h$"))
	end)

	it("returns a loaded site with a buffer and a tick", function()
		local target = assert(find(site_in("pair/math.c", 4, 2)))
		assert.is_truthy(target.buf)
		assert.are.equal(vim.b[target.buf].changedtick, target.tick)
	end)

	it("calls back with nil when there is no other side", function()
		assert.is_nil(find(site_in("static_proto/one.c", 4, 2)))
	end)
end)

describe("locate.find runner", function()
	after_each(wipe_buffers)

	it("calls back exactly once, even if a strategy settles twice", function()
		local source = site_in("static_proto/one.c", 9, 2)
		local decl = assert(parse.find_by_name(assert(source.buf), "helper", "declaration"))
		local calls = 0

		locate.find(source, function()
			calls = calls + 1
		end, {
			function(_, found, skip)
				found(decl)
				found(decl)
				skip()
			end,
		})

		vim.wait(200, function()
			return false
		end)
		assert.are.equal(1, calls)
	end)

	it("moves past a strategy that throws", function()
		local target = find(site_in("static_proto/one.c", 9, 2), {
			function()
				error("boom")
			end,
			locate.strategies[SAME_FILE],
		})
		assert.are.equal("declaration", assert(target).kind)
	end)

	it("always calls back asynchronously", function()
		local called = false
		locate.find(site_in("static_proto/one.c", 9, 2), function()
			called = true
		end, {})
		assert.is_false(called)
		assert.is_true(vim.wait(1000, function()
			return called
		end))
	end)
end)

describe("locate.find with clangd", function()
	local real_get_clients = vim.lsp.get_clients
	local real_timeout = locate.lsp_timeout_ms

	---Replaces clangd with a fake. `replies[method]` is a function returning the result,
	---or the string "never" to simulate a request clangd never answers.
	---@param replies table<string, (fun(params: table): any)|"never">
	local function fake_clangd(replies)
		local client = {
			offset_encoding = "utf-16",
			request = function(_, method, params, handler)
				local reply = replies[method]
				if reply == "never" then
					return true
				end
				local result = reply and reply(params) or nil
				vim.schedule(function()
					handler(nil, result)
				end)
				return true
			end,
		}
		---@diagnostic disable-next-line: duplicate-set-field
		vim.lsp.get_clients = function(filter)
			if filter and filter.name == "clangd" then
				return { client }
			end
			return real_get_clients(filter)
		end
	end

	after_each(function()
		vim.lsp.get_clients = real_get_clients
		locate.lsp_timeout_ms = real_timeout
		wipe_buffers()
	end)

	it("uses the location clangd returns", function()
		fake_clangd({
			["textDocument/declaration"] = function()
				return {
					uri = vim.uri_from_fname(FIXTURES .. "/pair/math.h"),
					range = { start = { line = 4, character = 4 }, ["end"] = { line = 4, character = 7 } },
				}
			end,
		})

		local target = find(site_in("pair/math.c", 4, 2), { locate.strategies[CLANGD] })
		assert.are.equal("math.h", file_of(target))
	end)

	it("sends the name's position in the client's encoding", function()
		local path = vim.fn.tempname() .. ".c"
		vim.fn.writefile({ "/*ø*/ int add(int a, int b) { return a + b; }" }, path)
		local sent

		fake_clangd({
			["textDocument/declaration"] = function(params)
				sent = params.position
				return nil
			end,
		})

		local buf = vim.fn.bufadd(path)
		vim.fn.bufload(buf)
		find(assert(parse.site_at(buf, 0, 20)), { locate.strategies[CLANGD] })

		-- `add` starts at byte 11, but `ø` is one UTF-16 unit, so character 10
		assert.are.same({ line = 0, character = 10 }, sent)
		os.remove(path)
	end)

	it("moves on when clangd never answers", function()
		vim.g.lockstep = { lsp_timeout_ms = 50 }
		fake_clangd({ ["textDocument/declaration"] = "never" })

		local target = find(site_in("pair/math.c", 4, 2), {
			locate.strategies[CLANGD],
			locate.strategies[INCLUDES],
		})
		assert.are.equal("math.h", file_of(target))
	end)

	it("searches the file switchSourceHeader points to", function()
		fake_clangd({
			["textDocument/switchSourceHeader"] = function()
				return vim.uri_from_fname(FIXTURES .. "/renamed/include/api.h")
			end,
		})

		local target = find(site_in("renamed/src/impl.c", 4, 2), { locate.strategies[SWITCH] })
		assert.are.equal("api.h", file_of(target))
	end)

	it("doesn't scan the project when project_scan is off", function()
		vim.g.lockstep = { project_scan = false }
		assert.is_nil(find(site_in("pair/math.h", 4, 4)))
	end)
end)
