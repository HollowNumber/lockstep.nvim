local edit = require("lockstep.edit")
local locate = require("lockstep.locate")
local parse = require("lockstep.parse")
local util = require("lockstep.util")

local M = {}

---@param source lockstep.Site
---@param on_done fun(result: lockstep.EditResult?)
---@param attempt integer
local function run(source, on_done, attempt)
	local want = source.kind == "definition" and "declaration" or "definition"

	locate.find(source, function(target)
		if not target then
			util.notify(("No %s found for %s()"):format(want, source.name), vim.log.levels.WARN)
			on_done(nil)
			return
		end

		local result = edit.apply(source, target)
		local file = vim.fs.basename(vim.api.nvim_buf_get_name(assert(target.buf)))

		if result == "stale" and attempt == 1 then
			-- A buffer changed during the lookup; find the source again where it is now
			local fresh = parse.find_by_name(assert(source.buf), source.name, source.kind, source.lang)
			if fresh then
				return run(fresh, on_done, attempt + 1)
			end
		end

		if result == "changed" then
			util.notify(
				("Updated %s of %s() in %s:%d (unsaved)"):format(want, source.name, file, target.range.start_row + 1)
			)
		elseif result == "unchanged" then
			util.notify(("%s() is already in sync with %s"):format(source.name, file))
		elseif result == "readonly" then
			util.notify(("Can't update %s: it's read-only"):format(file), vim.log.levels.WARN)
		elseif result == "stale" then
			util.notify("A file changed during the lookup, run the sync again", vim.log.levels.WARN)
		end

		on_done(result)
	end)
end

---Syncs the function signature at a position to its declaration or definition.
---Defaults to the current buffer and cursor.
---@param buf? integer
---@param row? integer 0-based
---@param col? integer 0-based
---@param on_done? fun(result: lockstep.EditResult?) Called once the sync finishes; nil if nothing was found
function M.sync(buf, row, col, on_done)
	on_done = on_done or function() end
	buf = buf or vim.api.nvim_get_current_buf()
	if not row or not col then
		local cursor = vim.api.nvim_win_get_cursor(0)
		row, col = cursor[1] - 1, cursor[2]
	end

	local site = parse.site_at(buf, row, col)
	if not site then
		util.notify("Cursor isn't on a function", vim.log.levels.WARN)
		on_done(nil)
		return
	end

	run(site, on_done, 1)
end

return M
