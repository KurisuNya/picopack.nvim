local Status = require('picopack.core.status')
local Build = require('picopack.core.build')
local Register = require('picopack.core.register')
local Load = require('picopack.core.load')
local Utils = require('picopack.utils')
local Safecall = require('picopack.safecall')

local M = {}

local start_enter = false
local start_init_done = false
local start_finished = false

local updating = false
local update_build_failed = false

-- register api

---@param name string
---@param options? {source?: "all"|"specs"|"deps"} source: default "all"
---@return boolean
M.is_registered = function(name, options)
  local source = (options or {}).source
  Utils.validate('name', name, 'string')
  local validator = function(value) return value == 'all' or value == 'specs' or value == 'deps' end
  Utils.validate('options.source', source, validator, true, 'must be "all", "specs", or "deps"')
  return Register.is_registered(name, { source = source or 'all' })
end

---@param options? {source?: "all"|"specs"|"deps"} source: default "all"
---@return string[]
M.registered = function(options)
  local source = (options or {}).source
  local validator = function(value) return value == 'all' or value == 'specs' or value == 'deps' end
  Utils.validate('options.source', source, validator, true, 'must be "all", "specs", or "deps"')
  return Register.registered({ source = source or 'all' })
end

---@param spec PicoPack.Spec
---@param strict boolean
M.register = function(spec, strict)
  Utils.validate('strict', strict, 'boolean')
  if start_enter then
    Utils.fail('register', 'cannot register after picopack start')
  end
  Register.register(spec, strict)
end

-- load api

---@param name string
---@return boolean
M.is_configured = function(name)
  Utils.validate('name', name, 'string')
  return Load.is_configured(name)
end

M.configured = Load.configured

---@param name string
---@param opts table | fun(): table
---@param options {extend?: string|string[], priority?: number, warn_if_configured?: boolean} priority: default 50, warn_if_configured: default true
M.opts_extend = function(name, opts, options)
  options = options or {}
  Utils.validate('name', name, 'string')
  Utils.validate('opts', opts, { 'table', 'function' })
  local extend, priority = options.extend, options.priority
  if vim.islist(extend) then
    ---@cast extend string[]
    for i, key in ipairs(extend) do
      Utils.validate(('%s[%d]'):format('option.extend', i), key, 'string')
    end
  else
    Utils.validate('options.extend', extend, 'string', true)
  end
  Utils.validate('options.priority', priority, 'number', true)
  local warn_if_configured = options.warn_if_configured
  Utils.validate('options.warn_if_configured', warn_if_configured, 'boolean', true)
  Load.opts_extend(name, opts, {
    extend = extend,
    priority = priority or 50,
    warn_if_configured = warn_if_configured ~= false,
  })
end

---@param name string
---@param fn fun()
M.before_config = function(name, fn)
  Utils.validate('name', name, 'string')
  Utils.validate('fn', fn, 'function')
  Load.before_config(name, fn)
end

---@param name string
---@param fn fun()
M.after_config = function(name, fn)
  Utils.validate('name', name, 'string')
  Utils.validate('fn', fn, 'function')
  Load.after_config(name, fn)
end

---@param name string
M.load_and_config = function(name)
  Utils.validate('name', name, 'string')
  if not start_init_done then
    Utils.fail(('load_and_config "%s"'):format(name), 'picopack start init phase not finished')
  end
  Load.load_and_config(name)
end

-- build api

---@param name string
---@param options {force: boolean, before_build?: fun(name: string), after_build?: fun(name: string)}
local build_with_notify = function(name, options)
  Build.build(name, {
    force = options.force,
    before_build = function(n)
      if options.before_build then
        options.before_build(n)
      end
      Utils.notify(('building plugin %s'):format(n), 'INFO')
    end,
    after_build = function(n)
      if options.after_build then
        options.after_build(n)
      end
      Utils.notify(('built plugin %s'):format(n), 'INFO')
    end,
  })
end

---@param name string
---@param options {force: boolean, before_build?: fun(name: string), after_build?: fun(name: string)}
local build_with_load = function(name, options)
  build_with_notify(name, {
    force = options.force,
    before_build = function(n)
      if options.before_build then
        options.before_build(n)
      end
      M.load_and_config(n)
    end,
    after_build = options.after_build,
  })
end

---@param name string
local pack_add = function(name)
  vim.cmd.packadd({ vim.fn.escape(name, ' '), bang = false, magic = { file = false } })
end

---@param name string
---@param options {force: boolean, before_build?: fun(name: string), after_build?: fun(name: string)}
local build_force_load = function(name, options)
  build_with_notify(name, {
    force = options.force,
    before_build = function(n)
      if options.before_build then
        options.before_build(n)
      end
      pack_add(n)
    end,
    after_build = options.after_build,
  })
end

---@param names string[]
---@param build_fn function
---@param options {force: boolean, before_build?: fun(name: string), after_build?: fun(name: string)}
---@return boolean success
local build_multi = function(names, build_fn, options)
  local success = true
  for _, name in ipairs(names) do
    success = Safecall.now(function() build_fn(name, options) end) and success
  end
  return success
end

M.is_pending_build = Build.is_pending

M.pending_builds = Build.pending

---@param name string
---@param options? {force?: boolean, before_build?: fun(name: string), after_build?: fun(name: string)} -- force: default true
M.build = function(name, options)
  Utils.validate('name', name, 'string', false)
  Utils.validate('options', options, 'table', true)
  options = options or {}
  Utils.validate('options.force', options.force, 'boolean', true)
  Utils.validate('options.before_build', options.before_build, 'function', true)
  Utils.validate('options.after_build', options.after_build, 'function', true)
  local force_load = update_build_failed or not start_init_done
  local build_fn = force_load and build_force_load or build_with_load
  build_fn(name, {
    force = options.force ~= false,
    before_build = options.before_build,
    after_build = options.after_build,
  })
end

---@param options? {before_build?: fun(name: string), after_build?: fun(name: string)}
---@return boolean success
M.build_pending = function(options)
  Utils.validate('options', options, 'table', true)
  options = options or {}
  Utils.validate('options.before_build', options.before_build, 'function', true)
  Utils.validate('options.after_build', options.after_build, 'function', true)
  local force_load = update_build_failed or not start_init_done
  local build_fn = force_load and build_force_load or build_with_load
  return build_multi(Build.pending(), build_fn, {
    force = false,
    before_build = options.before_build,
    after_build = options.after_build,
  })
end

-- status api

M.installed = Status.installed

M.loaded = Status.loaded

M.unmanaged = Status.unmanaged

M.stats = function()
  if not start_finished then
    Utils.fail('stats', 'picopack start not finished')
  end
  return Status.stats()
end

-- manage api

---@return table<string, vim.pack.PlugData>
local installed_vim_plugs = function()
  local installed = vim.pack.get(nil, { info = false })
  local map = {}
  for _, p in ipairs(installed) do
    map[p.spec.name] = p
  end
  return map
end

---@param specs vim.pack.SpecResolved[]
---@return boolean success
---@return boolean changed
local sync_vim_specs = function(specs)
  local installed = installed_vim_plugs()
  local missing, changed = {}, {}
  for _, spec in ipairs(specs) do
    local cur = installed[spec.name]
    if not cur then
      table.insert(missing, spec)
    elseif cur.spec.src ~= spec.src or not vim.deep_equal(cur.spec.version, spec.version) then
      table.insert(changed, spec)
    end
  end
  if #missing == 0 and #changed == 0 then
    return true, false
  end

  local ok = Safecall.now(function()
    if #changed > 0 then
      vim.pack.del(vim.tbl_map(function(spec) return spec.name end, changed))
    end
    vim.pack.add(specs, { load = false, confirm = false })
  end)

  local expected = {}
  vim.list_extend(expected, missing)
  vim.list_extend(expected, changed)
  local after = installed_vim_plugs()
  local absent = vim.tbl_filter(function(s) return not after[s.name] end, expected)
  return ok and #absent == 0, true
end

M.clean = function()
  if not start_finished then
    Utils.fail('clean', 'picopack start not finished')
  end
  local unmanaged = Status.unmanaged()
  if #unmanaged > 0 then
    Safecall.now(function() vim.pack.del(unmanaged) end)
  end
end

---@param confirm? boolean
M.update = function(confirm)
  Utils.validate('confirm', confirm, 'boolean', true)

  if not start_finished then
    Utils.fail('update', 'picopack start not finished')
  end
  if updating then
    Utils.fail('update', 'updating already in progress')
  end

  local group = vim.api.nvim_create_augroup('PicoPack.Core.update', { clear = true })
  updating = true
  local cleanup = function()
    pcall(vim.api.nvim_del_augroup_by_id, group)
    updating = false
  end

  local updated = {}
  local finish = function()
    if next(updated) == nil then
      return
    end
    local pending = vim.tbl_filter(function(n) return updated[n] end, Build.pending())
    if not build_multi(pending, build_force_load, { force = false }) then
      Utils.notify('failed to build some plugins, please rebuild manually and restart', 'ERROR')
      update_build_failed = true
      return
    end
    if not Safecall.now(function() vim.cmd('restart!') end) then
      Utils.notify('failed to restart after updating plugins, please restart manually', 'ERROR')
    end
  end

  local ok, err = Utils.pcall_with_trace(function()
    vim.api.nvim_create_autocmd('PackChanged', {
      group = group,
      callback = function(ev)
        if ev.data.kind == 'update' then
          updated[ev.data.spec.name] = true
        end
      end,
    })

    local names = Register.registered({ source = 'all' })
    if confirm ~= false then
      local confirm_bufnr
      vim.api.nvim_create_autocmd('FileType', {
        group = group,
        pattern = 'nvim-pack',
        once = true,
        callback = function(ev) confirm_bufnr = ev.buf end,
      })
      if not Safecall.now(function() vim.pack.update(names, { force = false }) end) then
        cleanup()
        return
      end
      if not confirm_bufnr then
        Utils.notify('confirmation buffer was not created; update cancelled', 'ERROR')
        cleanup()
        return
      end
      vim.api.nvim_create_autocmd('BufDelete', {
        group = group,
        buffer = confirm_bufnr,
        once = true,
        callback = function()
          cleanup()
          finish()
        end,
      })
    else
      if not Safecall.now(function() vim.pack.update(names, { force = true }) end) then
        cleanup()
        return
      end
      cleanup()
      finish()
    end
  end)

  if not ok then
    cleanup()
    Utils.fail('update', err)
  end
end

---@return boolean success
M.start = function()
  if start_enter then
    Utils.fail('start', 'picopack start already called')
  end
  start_enter = true

  local pico_specs = Register.pico_specs()
  local vim_specs = Register.vim_specs()
  Utils.list_sort_stable(pico_specs, function(x) return -x.priority end)

  -- sync plugins and restart
  local success, changed = sync_vim_specs(vim_specs)
  local build_ok = build_multi(Build.pending(), build_force_load, { force = false })
  if not success then
    Utils.notify('failed to sync some plugins', 'ERROR')
  end
  if not build_ok then
    Utils.notify('failed to build some plugins, please rebuild manually and restart', 'ERROR')
  end
  if not success or not build_ok then
    return false
  end
  if changed and not Safecall.now(function() vim.cmd('restart!') end) then
    Utils.notify('failed to restart after syncing plugins, please restart manually', 'ERROR')
    return false
  end

  -- run init functions
  for _, spec in ipairs(pico_specs) do
    local init = spec.init
    if init then
      if not Safecall.now(init) then
        Utils.notify(('init function for plugin %s failed'):format(spec[1].name), 'ERROR')
      end
    end
  end

  start_init_done = true

  -- split into startup, event, filetype plugins
  ---@type PicoPack.SpecResolved[]
  local startup_specs = {}
  ---@type PicoPack.SpecResolved[]
  local event_specs = {}
  ---@type PicoPack.SpecResolved[]
  local filetype_specs = {}
  for _, spec in ipairs(pico_specs) do
    if not spec.lazy then
      table.insert(startup_specs, spec)
    elseif #spec.event > 0 then
      table.insert(event_specs, spec)
    elseif #spec.filetype > 0 then
      table.insert(filetype_specs, spec)
    end
  end

  -- register event plugins
  for _, spec in ipairs(event_specs) do
    Safecall.when_events(spec.event, function() Load.load_and_config(spec[1].name) end)
  end

  -- register filetype plugins
  for _, spec in ipairs(filetype_specs) do
    Safecall.when_filetypes(spec.filetype, function() Load.load_and_config(spec[1].name) end)
  end

  -- register VeryLazy event
  Safecall.later(function() vim.api.nvim_exec_autocmds('User', { pattern = 'VeryLazy' }) end)

  -- load startup plugins
  for _, spec in ipairs(startup_specs) do
    Safecall.now(function() Load.load_and_config(spec[1].name) end)
  end

  -- compute stats
  if not Safecall.now(Status.update_stats) then
    Utils.notify('failed to compute stats', 'ERROR')
  end

  start_finished = true
  return true
end

return M
