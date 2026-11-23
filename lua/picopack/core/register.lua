local Utils = require('picopack.utils')
local Spec = require('picopack.spec')

local M = {}

local self_vim_spec = Utils.with_formatted_err(function()
  local ok, specs = pcall(vim.pack.get, { Utils.package_name }, { info = false })
  if not ok or #specs ~= 1 then
    Utils.fail('core', 'failed to get self vim spec: ' .. Utils.repr(specs))
  end
  return specs[1].spec
end)()
local self_pico_spec = Spec.normalize({ self_vim_spec }, true)

local vim_specs = { self_vim_spec } ---@type vim.pack.SpecResolved[]
local vim_specs_set = { [Utils.package_name] = true } ---@type table<string, boolean>
local pico_specs = { self_pico_spec } ---@type PicoPack.SpecResolved[]
local pico_specs_map = { [Utils.package_name] = self_pico_spec } ---@type table<string, PicoPack.SpecResolved>

---@param name string
---@param options {source: "all"|"specs"|"deps"}
---@return boolean
M.is_registered = function(name, options)
  if options.source == 'all' then
    return vim_specs_set[name] == true
  elseif options.source == 'specs' then
    return pico_specs_map[name] ~= nil
  elseif options.source == 'deps' then
    return vim_specs_set[name] == true and pico_specs_map[name] == nil
  else
    Utils.fail(
      ('is_registered "%s"'):format(name),
      ('invalid source %s'):format(Utils.repr(options.source))
    )
    ---@diagnostic disable-next-line: missing-return
  end
end

---@param options {source: "all"|"specs"|"deps"}
---@return string[]
M.registered = function(options)
  if options.source == 'all' then
    local specs = Utils.list_filter_same(vim_specs, function(s) return s.name end)
    return vim.tbl_map(function(s) return s.name end, specs)
  elseif options.source == 'specs' then
    return vim.tbl_map(function(s) return s[1].name end, pico_specs)
  elseif options.source == 'deps' then
    local specs = Utils.list_filter_same(vim_specs, function(s) return s.name end)
    local deps = vim.tbl_filter(function(s) return not pico_specs_map[s.name] end, specs)
    return vim.tbl_map(function(s) return s.name end, deps)
  else
    Utils.fail('registered', ('invalid source %s'):format(Utils.repr(options.source)))
    ---@diagnostic disable-next-line: missing-return
  end
end

---@param spec PicoPack.Spec
---@param strict boolean
M.register = function(spec, strict)
  local resolved = Spec.normalize(spec, strict)
  local name = resolved[1].name
  if M.is_registered(name, { source = 'specs' }) then
    Utils.fail(('register "%s"'):format(name), 'spec already registered')
  end
  table.insert(vim_specs, resolved[1])
  vim_specs_set[name] = true
  for _, dep in ipairs(resolved.dependencies) do
    table.insert(vim_specs, dep)
    vim_specs_set[dep.name] = true
  end
  table.insert(pico_specs, resolved)
  pico_specs_map[name] = resolved
end

---@param name string
---@return PicoPack.SpecResolved?
M.get_pico_spec = function(name) return pico_specs_map[name] end

---@return PicoPack.SpecResolved[]
M.pico_specs = function() return vim.deepcopy(pico_specs) end

---@return vim.pack.SpecResolved[]
M.vim_specs = function() return vim.deepcopy(vim_specs) end

return M
