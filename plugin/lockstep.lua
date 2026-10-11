if vim.g.loaded_lockstep then
	return
end
vim.g.loaded_lockstep = true

---@class lockstep.Subcommand
---@field impl fun(args: string[], opts: vim.api.keyset.create_user_command.command_args)
---@field complete? fun(arg_lead: string): string[]

---@type table<string, lockstep.Subcommand>
local subcommands = {
	sync = {
		impl = function()
			require("lockstep").sync()
		end,
	},
}

vim.api.nvim_create_user_command("Lockstep", function(opts)
	local name = opts.fargs[1]
	local args = vim.list_slice(opts.fargs, 2)
	local subcommand = subcommands[name]
	if not subcommand then
		vim.notify(("Lockstep: unknown subcommand %q"):format(name or ""), vim.log.levels.ERROR, { title = "lockstep" })
		return
	end
	subcommand.impl(args, opts)
end, {
	nargs = "+",
	desc = "lockstep: keep C declarations and definitions in sync",
	complete = function(arg_lead, cmdline)
		local name, sub_lead = cmdline:match("^%S*Lockstep!?%s+(%S+)%s+(%S*)$")
		if name and subcommands[name] and subcommands[name].complete then
			return subcommands[name].complete(sub_lead)
		end
		if cmdline:match("^%S*Lockstep!?%s+%S*$") then
			return vim.tbl_filter(function(key)
				return vim.startswith(key, arg_lead)
			end, vim.tbl_keys(subcommands))
		end
		return {}
	end,
})

vim.keymap.set("n", "<Plug>(lockstep-sync)", function()
	require("lockstep").sync()
end, { desc = "lockstep: sync the signature under the cursor" })

local group = vim.api.nvim_create_augroup("lockstep", { clear = true })

vim.api.nvim_create_autocmd("FileType", {
	pattern = { "c", "cpp" },
	group = group,

	callback = function(args)
		if not require("lockstep.config").get().code_action then
			return
		end
		require("lockstep.lsp").attach(args.buf)
	end,
})
