local Utils = require('picopack.utils')
local Register = require('picopack.core.register')

local M = {}

local pico_specs_configuring = {} ---@type table<string, boolean>
local pico_specs_configured = { [Utils.package_name] = true } ---@type table<string, boolean>

local before_config_hooks = {} ---@type table<string, fun()[]>
local after_config_hooks = {} ---@type table<string, fun()[]>
local opts_modifiers = {} ---@type table<string, { priority: number, fn: fun(opts: table|nil): table|nil }[]>

---@param name string
---@return boolean
M.is_configured = function(name) return pico_specs_configured[name] == true end

---@return string[]
M.configured = function()
  return vim.tbl_filter(
    function(name) return pico_specs_configured[name] end,
    Register.registered({ source = 'specs' })
  )
end

---@param name string
---@param fn fun(opts: table|nil): table|nil
---@param priority number
local register_opts_modifier = function(name, fn, priority)
  if not opts_modifiers[name] then
    opts_modifiers[name] = {}
  end
  Utils.list_insert_sorted(
    opts_modifiers[name],
    { fn = fn, priority = priority },
    function(x) return -x.priority end
  )
end

---@param name string
---@param opts table | fun(): table
---@param options {extend?: string|string[], priority: number, warn_if_configured: boolean}
M.opts_extend = function(name, opts, options)
  local extend, priority = options.extend, options.priority
  local warn_if_configured = options.warn_if_configured
  extend = type(extend) == 'string' and { extend } or extend --[=[@as string[]|nil]=]

  if warn_if_configured and pico_specs_configured[name] then
    local msg = ('opts_extend "%s" called after spec configured, will not be applied'):format(name)
    Utils.notify(msg, 'WARN')
  end

  local fn = function(old_opts)
    old_opts = old_opts or {}
    local new_opts
    if type(opts) == 'function' then
      new_opts = opts()
    else
      new_opts = opts
    end
    Utils.validate('opts', new_opts, 'table')
    local t = vim.tbl_deep_extend('force', vim.deepcopy(old_opts), vim.deepcopy(new_opts))
    for _, key in ipairs(extend or {}) do
      local path = vim.split(key, '.', { plain = true })
      local base = vim.tbl_get(old_opts, unpack(path))
      local add = vim.tbl_get(new_opts, unpack(path))
      base = base == nil and {} or base
      if not vim.islist(base) or not vim.islist(add) then
        Utils.fail(
          ('opts_extend %s'):format(name),
          ('cannot extend non-list table "%s"'):format(key)
        )
      end
      local merged = vim.list_extend({}, base)
      merged = vim.list_extend(merged, add)
      Utils.tbl_set(t, merged, unpack(path))
    end
    return t
  end
  register_opts_modifier(name, fn, priority)
end

---@param name string
---@param fn fun()
M.before_config = function(name, fn)
  if M.is_configured(name) then
    Utils.fail(('before_config "%s"'):format(name), 'already configured')
  end
  if not before_config_hooks[name] then
    before_config_hooks[name] = {}
  end
  table.insert(before_config_hooks[name], fn)
end

---@param name string
---@param fn fun()
M.after_config = function(name, fn)
  if M.is_configured(name) then
    fn()
    return
  end
  if not after_config_hooks[name] then
    after_config_hooks[name] = {}
  end
  table.insert(after_config_hooks[name], fn)
end

---@param name string
M.load_and_config = function(name)
  if pico_specs_configuring[name] or pico_specs_configured[name] then
    return
  end

  local fail_name = ('load "%s"'):format(name)
  local spec = Register.get_pico_spec(name)
  if not spec then
    Utils.fail(fail_name, 'not a picopack spec')
    error('unreachable')
  end

  pico_specs_configuring[name] = true
  local ok, err = Utils.pcall_with_trace(function()
    local specs = {}
    for _, dep in ipairs(spec.dependencies or {}) do
      if Register.is_registered(dep.name, { source = 'specs' }) then
        M.load_and_config(dep.name)
      else
        table.insert(specs, dep)
      end
    end

    table.insert(specs, spec[1])
    vim.pack.add(specs, { confirm = false })

    for _, hook in ipairs(before_config_hooks[name] or {}) do
      hook()
    end

    local opts = spec.opts
    if type(opts) == 'function' then
      opts = opts()
      Utils.validate('spec.opts', opts, 'table')
    end
    for i, modifier in ipairs(opts_modifiers[name] or {}) do
      opts = modifier.fn(opts)
      Utils.validate(('spec.opts after modifier[%d]'):format(i), opts, 'table', true)
    end

    if opts and not spec.config then
      Utils.fail('spec.opts', 'requires spec.config')
    end
    if spec.config then
      spec.config(opts or {})
    end

    for _, hook in ipairs(after_config_hooks[name] or {}) do
      hook()
    end
  end)
  pico_specs_configuring[name] = nil

  if not ok then
    Utils.fail(fail_name, err)
  end
  pico_specs_configured[name] = true
end

return M
