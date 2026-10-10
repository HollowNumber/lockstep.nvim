local M = {}

---Extracts the text of a site
---@param site lockstep.Site
---@return string[]
local function text_of(site)
	assert(site.buf, "lockstep: site has no buffer")

	return vim.api.nvim_buf_get_text(
		site.buf,
		site.range.start_row,
		site.range.start_col,
		site.range.end_row,
		site.range.end_col,
		{}
	)
end

---Applies a sync
---@param source lockstep.Site
---@param target lockstep.Site
---@return lockstep.EditResult
function M.apply(source, target)
	assert(source.buf, "lockstep: source site has no buffer")
	assert(target.buf, "lockstep: target site has no buffer")
	assert(source.tick, "lockstep: source site has no tick")
	assert(target.tick, "lockstep: target site has no tick")

	local source_tick = vim.b[source.buf].changedtick
	local target_tick = vim.b[target.buf].changedtick

	if source_tick ~= source.tick then
		return "stale"
	end

	if target_tick ~= target.tick then
		return "stale"
	end

	if not vim.bo[target.buf].modifiable then
		return "readonly"
	end

	local source_text = text_of(source)
	local target_text = text_of(target)

	if vim.deep_equal(source_text, target_text) then
		return "unchanged"
	end

	vim.api.nvim_buf_set_text(
		target.buf,
		target.range.start_row,
		target.range.start_col,
		target.range.end_row,
		target.range.end_col,
		source_text
	)

	vim.bo[target.buf].buflisted = true

	return "changed"
end

return M
