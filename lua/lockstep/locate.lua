local parse = require("lockstep.parse")
local util = require("lockstep.util")

local M = {}

local SCAN_LIMIT = 1000

local ROOT_MARKERS = { "compile_flags.txt", ".git", "Makefile" }

local SKIP_DIRS = {
	[".git"] = true,
	[".cache"] = true,
	build = true,
	node_modules = true,
}

local C_EXTENSIONS = { c = true, h = true, cc = true, cpp = true, hh = true, hpp = true }

--#region Helpers

---@param path string
---@return boolean
local function is_c_file(path)
	local ext = path:match("%.(%w+)$")
	return ext ~= nil and C_EXTENSIONS[ext] == true
end

---@param path string
---@return string?
local function read_file(path)
	local file = io.open(path, "rb")
	if not file then
		return nil
	end
	local text = file:read("*a")
	file:close()
	return text
end

---@param buf integer
---@param row integer
---@return string
local function line_of(buf, row)
	return vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
end

---@param buf integer
---@param pos lockstep.Pos
---@param encoding string
---@return integer
local function to_lsp_col(buf, pos, encoding)
	local line = line_of(buf, pos.row)
	return vim.str_utfindex(line, encoding, math.min(pos.col, #line), false)
end

---@param buf integer
---@param row integer
---@param col integer
---@param encoding string
---@return integer
local function from_lsp_col(buf, row, col, encoding)
	local line = line_of(buf, row)
	return vim.str_byteindex(line, encoding, col, false)
end

---@param path string
---@return integer
local function load(path)
	local buf = vim.fn.bufadd(path)
	vim.fn.bufload(buf)
	return buf
end

---@param buf integer
---@return vim.lsp.Client?
local function clangd(buf)
	return vim.lsp.get_clients({ bufnr = buf, name = "clangd" })[1]
end

---@param ctx lockstep.SyncContext
---@param path string
---@return lockstep.Site? site With `path` set, not `buf`
local function try_path(ctx, path)
	path = util.normalize_path(path)
	if path == "" or ctx.seen[path] then
		return nil
	end
	ctx.seen[path] = true

	local text = read_file(path)
	if not text then
		return nil
	end
	return parse.find_by_name(text, ctx.source.name, ctx.want, ctx.source.lang, path)
end

---`on_result` gets nil on error or timeout.
---@param ctx lockstep.SyncContext
---@param method string
---@param params table
---@param on_result fun(result: any, client: vim.lsp.Client)
---@return boolean sent
local function request(ctx, method, params, on_result)
	local buf = assert(ctx.source.buf)
	local client = clangd(buf)
	if not client then
		return false
	end

	local settled = false
	local timer

	local function settle(result)
		if settled then
			return
		end
		settled = true
		if timer and not timer:is_closing() then
			timer:stop()
			timer:close()
		end
		on_result(result, client)
	end

	local ok = client:request(method, params, function(err, result)
		settle(not err and result or nil)
	end, buf)
	if not ok then
		return false
	end

	timer = vim.defer_fn(function()
		settle(nil)
	end, require("lockstep.config").get().lsp_timeout_ms)
	return true
end

--#endregion

--#region Strategies

---@type lockstep.Strategy
local function clangd_lookup(ctx, found, skip)
	local buf = assert(ctx.source.buf)
	local client = clangd(buf)
	if not client then
		return skip()
	end

	local method = ctx.want == "definition" and "textDocument/definition" or "textDocument/declaration"
	local params = {
		textDocument = { uri = vim.uri_from_bufnr(buf) },
		position = {
			line = ctx.source.name_pos.row,
			character = to_lsp_col(buf, ctx.source.name_pos, client.offset_encoding),
		},
	}

	local sent = request(ctx, method, params, function(result, c)
		if not result then
			return skip()
		end

		-- Location, LocationLink, or a list of either
		local locations = (result.uri or result.targetUri) and { result } or result
		for _, loc in ipairs(locations) do
			local range = loc.targetSelectionRange or loc.range
			local uri = loc.targetUri or loc.uri
			if range and uri then
				local target = load(vim.uri_to_fname(uri))
				local row = range.start.line
				local col = from_lsp_col(target, row, range.start.character, c.offset_encoding)
				local site = parse.site_at(target, row, col, ctx.source.lang)
				if site and site.kind == ctx.want and site.name == ctx.source.name then
					return found(site)
				end
			end
		end
		skip()
	end)

	if not sent then
		skip()
	end
end

---@type lockstep.Strategy
local function same_file(ctx, found, skip)
	local site = parse.find_by_name(assert(ctx.source.buf), ctx.source.name, ctx.want, ctx.source.lang)
	if site then
		return found(site)
	end
	skip()
end

-- Still finds the file once changed parameters stop clangd linking the two
---@type lockstep.Strategy
local function switch_source_header(ctx, found, skip)
	local buf = assert(ctx.source.buf)
	local sent = request(ctx, "textDocument/switchSourceHeader", { uri = vim.uri_from_bufnr(buf) }, function(result)
		if type(result) ~= "string" then
			return skip()
		end
		local site = try_path(ctx, vim.uri_to_fname(result))
		if site then
			return found(site)
		end
		skip()
	end)

	if not sent then
		skip()
	end
end

---@type lockstep.Strategy
local function includes(ctx, found, skip)
	if ctx.want ~= "declaration" then
		return skip()
	end

	local buf = assert(ctx.source.buf)
	local dir = vim.fs.dirname(vim.api.nvim_buf_get_name(buf))
	for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
		local inc = line:match('^%s*#%s*include%s*"([^"]+)"')
		if inc then
			for _, base in ipairs({ dir, ctx.root, ctx.root .. "/include" }) do
				local site = try_path(ctx, base .. "/" .. inc)
				if site then
					return found(site)
				end
			end
		end
	end
	skip()
end

---@type lockstep.Strategy
local function open_buffers(ctx, found, skip)
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if buf ~= ctx.source.buf and vim.api.nvim_buf_is_loaded(buf) then
			local path = util.normalize_path(vim.api.nvim_buf_get_name(buf))
			if path ~= "" and is_c_file(path) and not ctx.seen[path] then
				ctx.seen[path] = true
				local site = parse.find_by_name(buf, ctx.source.name, ctx.want, ctx.source.lang)
				if site then
					return found(site)
				end
			end
		end
	end
	skip()
end

---@type lockstep.Strategy
local function project_scan(ctx, found, skip)
	local pattern = "%f[%w_]" .. vim.pesc(ctx.source.name) .. "%s*%("
	local count = 0

	for name, kind in
		vim.fs.dir(ctx.root, {
			depth = math.huge,
			skip = function(dir)
				return not SKIP_DIRS[vim.fs.basename(dir)]
			end,
		})
	do
		if kind == "file" and is_c_file(name) then
			count = count + 1
			if count > SCAN_LIMIT then
				break
			end

			local path = ctx.root .. "/" .. name
			local text = read_file(path)
			if text and text:find(pattern) then
				local site = try_path(ctx, path)
				if site then
					return found(site)
				end
			end
		end
	end
	skip()
end

---@type lockstep.Strategy[]
M.strategies = {
	clangd_lookup,
	same_file,
	switch_source_header,
	includes,
	open_buffers,
	project_scan,
}

--#endregion

--#region Runner

---@param ctx lockstep.SyncContext
---@param site lockstep.Site
---@return lockstep.Site? site With `buf` and `tick` set
local function resolve(ctx, site)
	if site.buf and site.tick then
		return site
	end
	if not site.path then
		return nil
	end

	local buf = load(site.path)
	local loaded = parse.site_at(buf, site.name_pos.row, site.name_pos.col, ctx.source.lang)
	if loaded and loaded.kind == ctx.want and loaded.name == ctx.source.name then
		return loaded
	end
	return nil
end

---@return lockstep.Strategy[]
local function default_strategies()
	if require("lockstep.config").get().project_scan then
		return M.strategies
	end
	return vim.tbl_filter(function(strategy)
		return strategy ~= project_scan
	end, M.strategies)
end

---Calls `callback` exactly once, always asynchronously.
---@param source lockstep.Site
---@param callback fun(target: lockstep.Site?)
---@param strategies? lockstep.Strategy[]
function M.find(source, callback, strategies)
	local buf = assert(source.buf, "lockstep: source site has no buffer")
	strategies = strategies or default_strategies()
	local path = util.normalize_path(vim.api.nvim_buf_get_name(buf))

	---@type lockstep.SyncContext
	local ctx = {
		source = source,
		want = source.kind == "definition" and "declaration" or "definition",
		root = vim.fs.root(buf, ROOT_MARKERS) or (path ~= "" and vim.fs.dirname(path)) or vim.fn.getcwd(),
		seen = path ~= "" and { [path] = true } or {},
	}

	local function run(i)
		local strategy = strategies[i]
		if not strategy then
			return vim.schedule(function()
				callback(nil)
			end)
		end

		local settled = false

		local function skip()
			if settled then
				return
			end
			settled = true
			run(i + 1)
		end

		local function found(site)
			if settled then
				return
			end
			settled = true
			-- Scheduled so the callback runs outside the strategy's pcall
			vim.schedule(function()
				local ok, target = pcall(resolve, ctx, site)
				if ok and target then
					callback(target)
				else
					run(i + 1)
				end
			end)
		end

		local ok, err = pcall(strategy, ctx, found, skip)
		if not ok then
			vim.schedule(function()
				util.notify("lookup step failed: " .. tostring(err), vim.log.levels.DEBUG)
			end)
			skip()
		end
	end

	run(1)
end

--#endregion

return M
