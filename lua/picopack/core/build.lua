local Utils = require('picopack.utils')
local Register = require('picopack.core.register')

local pending = {} ---@type table<string, boolean>
local building = {} ---@type table<string, boolean>

vim.api.nvim_create_autocmd('PackChanged', {
  group = vim.api.nvim_create_augroup('PicoPack.Build', { clear = true }),
  callback = function(ev)
    if ev.data.kind == 'install' or ev.data.kind == 'update' then
      pending[ev.data.spec.name] = true
    end
  end,
})

---@param name string
local pack_add = function(name)
  vim.cmd.packadd({ vim.fn.escape(name, ' '), bang = true, magic = { file = false } })
end

---@param path string
---@param build string|fun(path: string)
local run_build = function(path, build)
  if type(build) == 'string' then
    local shell = vim.env.SHELL or vim.o.shell
    local shell_args = shell:find('cmd.exe', 1, true) and '/c' or '-c'
    local result = vim.system({ shell, shell_args, build }, { cwd = path, text = true }):wait()
    if result.code ~= 0 then
      local stderr = result.stderr or ''
      local stdout = result.stdout or ''
      local output = stderr ~= '' and stderr or stdout
      Utils.fail(
        ('build cmd "%s"'):format(build),
        output ~= '' and output or 'No output from build command'
      )
    end
  else
    build(path)
  end
end

local M = {}

---@param name string
---@return boolean
M.is_pending = function(name)
  local spec = Register.get_pico_spec(name)
  local spec_valid = (spec and spec.build) ~= nil
  return spec_valid and pending[name] == true
end

---@return string[]
M.pending = function()
  local names = Register.registered({ source = 'specs' })
  return vim.tbl_filter(function(name) return M.is_pending(name) end, names)
end

---@param name string
---@param options {force: boolean, before_build?: fun(name: string), after_build?: fun(name: string)}
M.build = function(name, options)
  if not options.force and not pending[name] then
    return
  end
  if building[name] then
    return
  end

  local fail_name = ('build %s'):format(name)
  local spec = Register.get_pico_spec(name)
  if not spec then
    Utils.fail(fail_name, 'not a picopack spec')
    error('unreachable')
  end
  if not spec.build then
    Utils.fail(fail_name, 'spec.build is not defined')
  end

  local plug = vim.pack.get({ name }, { info = false })[1]
  if not plug then
    Utils.fail(fail_name, 'not installed')
  end

  building[name] = true
  local ok, err = Utils.pcall_with_trace(function()
    for _, dep in ipairs(spec.dependencies) do
      pack_add(dep.name)
    end
    pack_add(name)
    if options.before_build then
      options.before_build(name)
    end
    run_build(plug.path, spec.build)
    if options.after_build then
      options.after_build(name)
    end
  end)
  building[name] = nil

  if not ok then
    Utils.fail(fail_name, err)
  end
  pending[name] = nil
end

return M
