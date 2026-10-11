local M = {}

local warned = false

---@type lockstep.Config
local defaults = {
	code_action = false,
	lsp_timeout_ms = 1000,
	project_scan = true,
}

---@param key string
---@param value any
---@return string? problem
local function check(key, value)
	local default = defaults[key]
	if default == nil then
		return "unknown option: " .. key
	end
	if type(value) ~= type(default) then
		return ("%s should be a %s, got %s"):format(key, type(default), type(value))
	end
	if key == "lsp_timeout_ms" and value <= 0 then
		return "lsp_timeout_ms must be positive, got " .. tostring(value)
	end
end

---@param user any The value of vim.g.lockstep
---@return string[] problems
function M.validate(user)
	if user == nil then
		return {}
	end

	if type(user) ~= "table" then
		return { "vim.g.lockstep must be a table" }
	end

	local problems = {}

	for key, value in pairs(user) do
		local problem = check(key, value)
		if problem then
			table.insert(problems, problem)
		end
	end

	return problems
end

---@return lockstep.Config
function M.get()
	local user = vim.g.lockstep

	if not warned then
		local problems = M.validate(user)
		if #problems > 0 then
			warned = true
			require("lockstep.util").notify(
				"invalid vim.g.lockstep, using defaults for:\n" .. table.concat(problems, "\n"),
				vim.log.levels.WARN
			)
		end
	end

	local config = vim.deepcopy(defaults)

	if type(user) == "table" then
		for key, value in pairs(user) do
			if not check(key, value) then
				config[key] = value
			end
		end
	end

	return config
end

return M
