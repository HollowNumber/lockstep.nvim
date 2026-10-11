local M = {}

---@type lockstep.Action[]
M.list = {
	{
		id = "sync",
		kind = "refactor.rewrite",
		title = function(ctx)
			assert(ctx.site, "lockstep: sync title needs a site")
			local want = ctx.site.kind == "definition" and "declaration" or "definition"
			return "Sync signature to " .. want
		end,
		available = function(ctx)
			local site = ctx.site
			return site ~= nil
		end,
		offer = function(ctx)
			local site = ctx.site
			return site ~= nil and ctx.row >= site.range.start_row and ctx.row <= site.range.end_row
		end,
		run = function(ctx)
			require("lockstep").sync(ctx.buf, ctx.row, ctx.col)
		end,
	},
}

---@param id string
---@return lockstep.Action?
function M.get(id)
	for _, action in ipairs(M.list) do
		if action.id == id then
			return action
		end
	end
end

---@param buf integer
---@param row integer 0-based
---@param col integer 0-based
---@return lockstep.ActionContext
function M.context(buf, row, col)
	local site = require("lockstep.parse").site_at(buf, row, col)

	return {
		buf = buf,
		row = row,
		col = col,
		site = site,
	}
end

return M
