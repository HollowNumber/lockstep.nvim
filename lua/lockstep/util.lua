local M = {}

---Calls vim.notify with lockstep title
---@param msg string
---@param level? integer
function M.notify(msg, level)
	vim.notify(msg, level or vim.log.levels.INFO, { title = "lockstep" })
end

---Helper function to check for nil or empty
---@param s? string
---@return boolean
function M.isempty(s)
	return s == nil or s == ""
end

---Tries to resolve a normalized path
---@param path string
---@return string
function M.normalize_path(path)
	if M.isempty(path) then
		return ""
	end

	local norm = vim.fs.normalize(path)
	local real = vim.uv.fs_realpath(norm)

	if real == nil then
		return norm
	end

	return vim.fs.normalize(real)
end

return M
