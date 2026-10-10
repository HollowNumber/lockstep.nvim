local M = {}

local FN_NODES = { function_definition = true, declaration = true }

-- Leading children that belong to one side only and must not be copied across
local SKIP_PREFIX = {
	storage_class_specifier = true, -- static, extern, inline
	attribute_specifier = true,
	attribute_declaration = true,
	ms_declspec_modifier = true,
	comment = true,
}

---Walks the declarator chain (pointers, parentheses) down to the function declarator.
---@param node TSNode
---@return TSNode?
local function function_declarator(node)
	local decl = node:field("declarator")[1]
	while decl do
		if decl:type() == "function_declarator" then
			return decl
		end
		decl = decl:field("declarator")[1]
	end
end

---A function definition or a function prototype (not a variable declaration).
---@param node TSNode
---@return boolean
local function is_function(node)
	return FN_NODES[node:type()] == true and function_declarator(node) ~= nil
end

---@param node TSNode
---@param source integer|string Buffer number or source text
---@return string? name
---@return TSNode? node
local function function_name(node, source)
	local decl = function_declarator(node)
	local name = decl and decl:field("declarator")[1]
	if not name then
		return nil
	end
	-- `Foo::bar` and `bar` should match each other
	return vim.treesitter.get_node_text(name, source):match("([%w_~]+)$"), name
end

---From the return type (or first qualifier) to the end of the declarator.
---Nil when the signature is incomplete, e.g. while it is being typed.
---@param node TSNode
---@return lockstep.Range?
local function signature_range(node)
	local first
	for child in node:iter_children() do
		if child:named() and not SKIP_PREFIX[child:type()] then
			first = child
			break
		end
	end

	local declarator = node:field("declarator")[1]
	if not first or not declarator or declarator:has_error() then
		return nil
	end

	local sr, sc = first:range()
	local _, _, er, ec = declarator:range()
	return { start_row = sr, start_col = sc, end_row = er, end_col = ec }
end

---Parses a buffer or a string.
---For a buffer, its own language is tried first and `lang` is the fallback
---(headers detected as cpp still parse fine with the C parser).
---For a string there is no filetype, so `lang` is required.
---@param source integer|string
---@param lang? string
---@return TSNode? root
---@return string? lang The language that worked
local function parse(source, lang)
	if type(source) == "string" then
		if not lang then
			return nil
		end
		local ok, parser = pcall(vim.treesitter.get_string_parser, source, lang)
		if ok and parser then
			return parser:parse()[1]:root(), lang
		end
		return nil
	end

	local ft = vim.bo[source].filetype
	if ft == "" then
		ft = vim.filetype.match({ buf = source }) or ""
	end

	local langs = {}
	local own = ft ~= "" and vim.treesitter.language.get_lang(ft) or nil
	if own then
		table.insert(langs, own)
	end
	if lang and lang ~= own then
		table.insert(langs, lang)
	end
	-- .h files are filetype cpp by default, and Neovim only bundles the C parser
	if not vim.list_contains(langs, "c") then
		table.insert(langs, "c")
	end

	for _, l in ipairs(langs) do
		local ok, parser = pcall(vim.treesitter.get_parser, source, l)
		if ok and parser then
			return parser:parse()[1]:root(), l
		end
	end
end

---Innermost function definition or declaration containing a position.
---@param root TSNode
---@param row integer 0-based
---@param col integer 0-based
---@return TSNode?
local function function_at(root, row, col)
	local node = root:named_descendant_for_range(row, col, row, col)
	while node and not is_function(node) do
		node = node:parent()
	end
	return node
end

---@type table<string, vim.treesitter.Query|false>
local queries = {}

---@param lang string
---@return vim.treesitter.Query?
local function function_query(lang)
	if queries[lang] == nil then
		local ok, q = pcall(vim.treesitter.query.parse, lang, "[(function_definition) (declaration)] @fn")
		queries[lang] = ok and q or false
	end
	return queries[lang] or nil
end

---@param node TSNode
---@return lockstep.Kind
local function kind_of(node)
	return node:type() == "function_definition" and "definition" or "declaration"
end

---Builds a Site from a function node. Nil if any part of it is missing.
---@param node TSNode
---@param source integer|string
---@param lang string
---@param path? string Only for string sources: the file the text came from
---@return lockstep.Site?
local function to_site(node, source, lang, path)
	local name, name_node = function_name(node, source)
	local range = signature_range(node)
	if not name or not range or not name_node then
		return nil
	end

	local row, col = name_node:start()

	return {
		buf = type(source) == "number" and source or nil,
		tick = type(source) == "number" and vim.b[source].changedtick or nil,
		path = path,
		kind = kind_of(node),
		name = name,
		range = range,
		lang = lang,
		name_pos = { row = row, col = col },
	}
end

---@param buf integer
---@param row integer 0-based
---@param col integer 0-based
---@param lang? string Fallback if the buffer's own language has no parser
---@return lockstep.Site?
function M.site_at(buf, row, col, lang)
	local root, used = parse(buf, lang)
	if not root or not used then
		return nil
	end

	local node = function_at(root, row, col)
	if not node then
		return nil
	end

	return to_site(node, buf, used)
end

---The first function of the wanted kind with the given name.
---Does not exclude the source site itself; that is up to the caller.
---@param source integer|string Buffer number or file contents
---@param name string
---@param want lockstep.Kind
---@param lang? string Fallback for buffers, required for strings
---@param path? string Only for string sources: the file the text came from
---@return lockstep.Site?
function M.find_by_name(source, name, want, lang, path)
	local root, used = parse(source, lang)
	local query = root and used and function_query(used)
	if not root or not used or not query then
		return nil
	end

	for _, node in query:iter_captures(root, source) do
		if is_function(node) and kind_of(node) == want and function_name(node, source) == name then
			local site = to_site(node, source, used, path)
			if site then
				return site
			end
		end
	end
end

return M
