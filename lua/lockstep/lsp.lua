local actions = require("lockstep.actions")
local util = require("lockstep.util")
local M = {}

M.COMMAND = "lockstep.action"

---@param params lsp.CodeActionParams
---@return lsp.CodeAction[]
local function code_actions(params)
	local buf = vim.uri_to_bufnr(params.textDocument.uri)
	if not vim.api.nvim_buf_is_loaded(buf) then
		return {}
	end

	local row, col = params.range.start.line, params.range.start.character
	local ctx = actions.context(buf, row, col)

	local results = {}

	for _, action in ipairs(actions.list) do
		local offer = action.offer or action.available

		if offer(ctx) then
			local title = action.title(ctx)

			table.insert(results, {
				title = title,
				kind = action.kind,
				command = {
					title = title,
					command = M.COMMAND,
					arguments = {
						action.id,
						params.textDocument.uri,
						row,
						col,
					},
				},
			})
		end
	end
	return results
end

---@param command lsp.Command
local function execute(command)
	local args = command.arguments --[[@as any[] ]]
	---@type string, string, integer, integer
	local id, uri, row, col = unpack(args)

	local action = actions.get(id)

	if not action then
		util.notify("unknown action " .. id, vim.log.levels.WARN)
		return
	end

	local buf = vim.uri_to_bufnr(uri)
	local ctx = actions.context(buf, row, col)
	local available = action.available(ctx)

	if not available then
		util.notify("nothing to do here", vim.log.levels.WARN)
		return
	end

	action.run(ctx)
end

vim.lsp.commands[M.COMMAND] = execute

---@param dispatchers vim.lsp.rpc.Dispatchers
---@return vim.lsp.rpc.PublicClient
local function server(dispatchers)
	local closing = false
	local next_id = 0

	local function reply(callback, notify_reply, id, result)
		vim.schedule(function()
			callback(nil, result)
			if notify_reply then
				notify_reply(id)
			end
		end)
	end

	return {
		request = function(method, params, callback, notify_reply)
			next_id = next_id + 1
			if method == "initialize" then
				reply(callback, notify_reply, next_id, { capabilities = { codeActionProvider = true } })
			elseif method == "textDocument/codeAction" then
				local ok, results = pcall(code_actions, params)
				reply(callback, notify_reply, next_id, ok and results or {})
			else
				reply(callback, notify_reply, next_id, vim.NIL)
			end
			return true, next_id
		end,
		notify = function(method)
			if method == "exit" then
				dispatchers.on_exit(0, 15)
			end
		end,
		is_closing = function()
			return closing
		end,
		terminate = function()
			closing = true
		end,
	}
end

---@param buf integer
---@return integer?
function M.attach(buf)
	local client_id = vim.lsp.start({
		name = "lockstep",
		cmd = server,
		root_dir = vim.fs.root(buf, {
			"compile_flags.txt",
			".git",
		}) or vim.fn.getcwd(),
	}, {
		bufnr = buf,
	})

	return client_id
end

return M
