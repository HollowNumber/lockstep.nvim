---@meta
-- Type definitions

---@alias lockstep.Kind "definition"|"declaration"

---@class lockstep.Range
---@field start_row integer
---@field start_col integer
---@field end_row integer
---@field end_col integer

---@class lockstep.Site
---@field buf integer
---@field kind lockstep.Kind
---@field name string
---@field range lockstep.Range
---@field lang string Parser language that succeeded

---@class lockstep.SyncContext
---@field source lockstep.Site
---@field want lockstep.Kind
---@field root string Project root

---@alias lockstep.Strategy fun(ctx: lockstep.SyncContext, found: fun(site: lockstep.Site), next: fun())

---@alias lockstep.EditResult "changed"|"unchanged"
