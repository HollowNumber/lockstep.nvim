---@meta
---Type definitions

---Which side of a function a site is.
---@alias lockstep.Kind "definition"|"declaration"

---@class lockstep.Range
---@field start_row integer
---@field start_col integer
---@field end_row integer
---@field end_col integer

---@class lockstep.Site
---@field buf? integer
---@field path? string
---@field kind lockstep.Kind
---@field name string
---@field range lockstep.Range
---@field lang string
---@field tick? integer

---@class lockstep.SyncContext
---@field source lockstep.Site
---@field want lockstep.Kind
---@field root string

---@alias lockstep.Strategy fun(ctx: lockstep.SyncContext, found: fun(site: lockstep.Site), next: fun())

---@alias lockstep.EditResult "changed"|"unchanged"|"readonly"|"stale"
