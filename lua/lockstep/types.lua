---@meta
---Type definitions

---Which side of a function a site is.
---@alias lockstep.Kind "definition"|"declaration"

---@class lockstep.Range
---@field start_row integer
---@field start_col integer
---@field end_row integer
---@field end_col integer

---@class lockstep.Pos
---@field row integer
---@field col integer

---@class lockstep.Site
---@field buf? integer
---@field path? string
---@field kind lockstep.Kind
---@field name string
---@field range lockstep.Range
---@field lang string
---@field tick? integer
---@field name_pos lockstep.Pos

---@class lockstep.SyncContext
---@field source lockstep.Site
---@field want lockstep.Kind
---@field root string
---@field seen table<string, true> Normalized paths already searched

---A lookup strategy. Calls exactly one of `found` or `skip`.
---@alias lockstep.Strategy fun(ctx: lockstep.SyncContext, found: fun(site: lockstep.Site), skip: fun())

---@alias lockstep.EditResult "changed"|"unchanged"|"readonly"|"stale"

---@class lockstep.Action
---@field id string
---@field kind string LSP code action kind, e.g. "refactor.rewrite"
---@field title fun(ctx: lockstep.ActionContext): string
---@field available fun(ctx: lockstep.ActionContext): boolean
---@field offer? fun(ctx: lockstep.ActionContext): boolean
---@field run fun(ctx: lockstep.ActionContext)

---@class lockstep.ActionContext
---@field buf integer
---@field row integer 0-based
---@field col integer 0-based
---@field site lockstep.Site? Function signature at the position, if any

---@class lockstep.Config
---@field code_action boolean Offer lockstep's actions in the code-action menu
---@field lsp_timeout_ms integer How long to wait for clangd before trying the next strategy
---@field project_scan boolean Scan the project's files when nothing else finds the other side

---@class lockstep.UserConfig
---@field code_action? boolean
---@field lsp_timeout_ms? integer
---@field project_scan? boolean
