---@class (exact) PicoPack.Event
---@field name vim.api.keyset.events|vim.api.keyset.events[]
---@field pattern? string|string[]

---@class (exact) PicoPack.EventResolved
---@field name vim.api.keyset.events[]
---@field pattern? string[]

---@class (exact) PicoPack.Spec
---@field [1] string|vim.pack.Spec Plugin source or spec
---@field dependencies? string|vim.pack.Spec|(string|vim.pack.Spec)[]
---@field build? string|fun(path: string)
---@field init? fun()
---@field opts? table|fun(): table
---@field config? fun(opts: table)
---@field lazy? boolean
---@field priority? number
---@field event? string|PicoPack.Event|(string|PicoPack.Event)[]
---@field filetype? string|string[]

---@class (exact) PicoPack.SpecResolved
---@field [1] vim.pack.SpecResolved
---@field dependencies vim.pack.SpecResolved[] Empty list if nil
---@field build? string|fun(path: string)
---@field init? fun()
---@field opts? table|fun(): table
---@field config? fun(opts: table)
---@field lazy boolean Defaults to true
---@field priority number Defaults to 50
---@field event PicoPack.EventResolved[]
---@field filetype string[]

---@class (exact) PicoPack.Stats
---@field loaded integer
---@field installed integer
---@field unmanaged integer
---@field startuptime number In milliseconds

---@class (exact) PicoPack.Config
---@field check_spec_unknown_keys? boolean Defaults to true

---@class (exact) PicoPack.Trace
---@field name string
---@field msg string

---@generic T
---@param list T[]
---@return table<T, boolean>
local to_set = function(list)
  local s = {}
  for _, v in ipairs(list) do
    s[v] = true
  end
  return s
end

local M = {
  event_keys = to_set({
    'name',
    'pattern',
  }),
  vim_spec_keys = to_set({
    'src',
    'name',
    'version',
    'data',
  }),
  spec_keys = to_set({
    1, -- spec[1]
    'dependencies',
    'build',
    'init',
    'opts',
    'config',
    'lazy',
    'priority',
    'event',
    'filetype',
  }),
}

---@generic T
---@param tbl table<T, any>
---@param known_keys table<T,boolean>
---@return T[] unknown_keys
M.filter_unknown_keys = function(tbl, known_keys)
  local keys = vim.tbl_filter(function(k) return not known_keys[k] end, vim.tbl_keys(tbl))
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  return keys
end

return M
