local Time = require('picopack.time')
local Utils = require('picopack.utils')
local Register = require('picopack.core.register')

local M = {}

local stats = nil ---@type PicoPack.Stats?

---@return string[]
M.installed = function()
  local installed = vim.pack.get(nil, { info = false })
  return vim.tbl_map(function(p) return p.spec.name end, installed)
end

---@return string[]
M.loaded = function()
  local installed = vim.pack.get(nil, { info = false })
  local loaded = vim.tbl_filter(function(p) return p.active end, installed)
  return vim.tbl_map(function(p) return p.spec.name end, loaded)
end

---@return string[]
M.unmanaged = function()
  local registered = Utils.list_to_set(Register.registered({ source = 'all' }))
  return vim.tbl_filter(function(name) return not registered[name] end, M.installed())
end

M.update_stats = function()
  local installed = vim.pack.get(nil, { info = false })
  local loaded = vim.tbl_filter(function(p) return p.active end, installed)
  local registered = Utils.list_to_set(Register.registered({ source = 'all' }))
  local unmanaged = vim.tbl_filter(function(p) return not registered[p.spec.name] end, installed)
  stats = {
    loaded = #loaded,
    installed = #installed,
    unmanaged = #unmanaged,
    startuptime = Time.elapsed_ms(),
  }
end

---@return PicoPack.Stats?
M.stats = function() return stats end

return M
