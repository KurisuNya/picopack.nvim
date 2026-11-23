local Types = require('picopack.types')
local Utils = require('picopack.utils')

---@generic T
---@param path string
---@param tbl table<T, any>
---@param keys table<T, boolean>
local validate_keys = function(path, tbl, keys)
  local unknown = Types.filter_unknown_keys(tbl, keys)
  if #unknown > 0 then
    local keys_str = table.concat(vim.tbl_map(function(k) return Utils.repr(k) end, unknown), ', ')
    Utils.fail(path, ('unexpected %s %s'):format(#unknown == 1 and 'key' or 'keys', keys_str))
  end
end

---@param x string|vim.VersionRange
local is_version = function(x)
  if type(x) == 'string' then
    return true
  end
  if type(x) ~= 'table' then
    return false
  end
  local ok, res = pcall(x.has, x, '1')
  return ok and type(res) == 'boolean'
end

---@param x string
local is_nonempty_string = function(x) return type(x) == 'string' and x ~= '' end

---@param path string
---@param str string
---@return string
local norm_string = function(path, str)
  Utils.validate(path, str, 'string')
  return str
end

---@param path string
---@param str string
---@return string
local norm_nonempty_string = function(path, str)
  Utils.validate(path, str, is_nonempty_string, false, 'non-empty string')
  return str
end

---@generic T,J -- T should not be a list
---@param path string
---@param list T|T[]
---@param fn fun(path: string, item: T): J
---@return J[]
local norm_nested = function(path, list, fn)
  if vim.islist(list) then
    local out = {}
    for i, s in ipairs(list) do
      out[i] = fn(('%s[%d]'):format(path, i), s)
    end
    return out
  end
  return { fn(path, list) }
end

---@param path string
---@param event string|PicoPack.Event
---@param strict boolean
---@return PicoPack.EventResolved
local norm_event = function(path, event, strict)
  event = type(event) == 'string' and { name = event } or event
  Utils.validate(path, event, 'table')
  if strict then
    ---@cast event PicoPack.Event
    validate_keys(path, event, Types.event_keys)
  end

  local name = norm_nested(path .. '.name', event.name, norm_nonempty_string)
  local pattern = event.pattern and norm_nested(path .. '.pattern', event.pattern, norm_string)
  if #name == 0 then
    Utils.fail(path .. '.name', 'must not be empty')
  end
  return { name = name, pattern = pattern }
end

---@param path string
---@param spec string|vim.pack.Spec
---@param strict boolean
---@return vim.pack.SpecResolved
local norm_vim_spec = function(path, spec, strict)
  spec = type(spec) == 'string' and { src = spec } or spec
  Utils.validate(path, spec, 'table')
  if strict then
    ---@cast spec vim.pack.Spec
    validate_keys(path, spec, Types.vim_spec_keys)
  end

  local name, src = spec.name, spec.src
  src = norm_nonempty_string(path .. '.src', src)
  name = name ~= nil and norm_nonempty_string(path .. '.name', name) or src:gsub('%.git$', '')
  name = name:match('[^/]+$')
  if not name then
    local err_path = path .. (spec.name and '.name' or '.src')
    local err_fmt = spec.name and 'invalid name %s' or 'cannot derive a name from %s'
    Utils.fail(err_path, err_fmt:format(Utils.repr(spec.name or src)))
  end
  Utils.validate(path .. '.version', spec.version, is_version, true, 'string or vim.VersionRange')
  return { src = src, name = name, version = spec.version, data = spec.data }
end

local M = {}

---@param spec PicoPack.Spec
---@param strict boolean
---@return PicoPack.SpecResolved
M.normalize = function(spec, strict)
  Utils.validate('spec', spec, 'table')
  if strict then
    validate_keys('spec', spec, Types.spec_keys)
  end

  local norm_vim_spec_ = function(path, s) return norm_vim_spec(path, s, strict) end
  local norm_event_ = function(path, e) return norm_event(path, e, strict) end
  -- vim spec, dependencies
  Utils.validate('spec[1]', spec[1], { 'string', 'table' })
  local vim_spec = norm_vim_spec_('spec[1]', spec[1])
  local deps = norm_nested('spec.dependencies', spec.dependencies or {}, norm_vim_spec_)
  -- build, init, opts, config
  Utils.validate('spec.build', spec.build, { 'string', 'function' }, true)
  Utils.validate('spec.init', spec.init, 'function', true)
  Utils.validate('spec.opts', spec.opts, { 'table', 'function' }, true)
  Utils.validate('spec.config', spec.config, 'function', true)
  if spec.opts and not spec.config then
    Utils.fail('spec.opts', 'requires spec.config')
  end
  -- lazy, priority
  Utils.validate('spec.lazy', spec.lazy, 'boolean', true)
  Utils.validate('spec.priority', spec.priority, 'number', true)
  local lazy = spec.lazy ~= false -- default to true
  local priority = spec.priority or 50 -- default to 50
  -- event, filetype
  local event = norm_nested('spec.event', spec.event or {}, norm_event_)
  local filetype = norm_nested('spec.filetype', spec.filetype or {}, norm_string)
  if #event > 0 and #filetype > 0 then
    Utils.fail('spec', 'mutually exclusive keys "event", "filetype"')
  end

  return {
    vim_spec,
    dependencies = deps,
    build = spec.build,
    init = spec.init,
    opts = spec.opts,
    config = spec.config,
    lazy = lazy,
    priority = priority,
    event = event,
    filetype = filetype,
  }
end

return M
