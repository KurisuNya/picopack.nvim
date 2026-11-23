local M = {}

local msg_fmt = '(picopack) %s'

---@param value any
---@return string
M.repr = function(value) return vim.inspect(value, { newline = ' ', indent = '', depth = 1 }) end

---@param msg string
---@param level "TRACE"|"DEBUG"|"INFO"|"WARN"|"ERROR"|"OFF"
M.notify = function(msg, level)
  vim.notify(msg_fmt:format(msg), vim.log.levels[level], { title = 'picopack' })
end

---@param name string
---@param msg string
M.fail = function(name, msg) error(('%s: %s'):format(name, msg), 2) end

---@param fn function
---@param ... any
---@return boolean ok
---@return any result
---@return any ...
M.pcall_with_trace = function(fn, ...)
  return xpcall(fn, function(e)
    e = type(e) == 'string' and e or M.repr(e)
    return debug.traceback(e, 2)
  end, ...)
end

---@param ok boolean
---@param ... any
---@return boolean ok
---@return any ...
local pack_results = function(ok, ...) return ok, { n = select('#', ...), ... } end

---@generic T: function
---@param fn T
---@return T
M.with_formatted_err = function(fn)
  return function(...)
    local ok, res = pack_results(M.pcall_with_trace(fn, ...))
    if not ok then
      error(msg_fmt:format(res[1]), 0)
    end
    return unpack(res, 1, res.n)
  end
end

---@param path string
---@return string
M.normalize_path = function(path) return vim.uv.fs_realpath(path) or vim.fs.normalize(path) end

M.package_path, M.package_name = (function()
  local source = debug.getinfo(1, 'S').source
  if source:sub(1, 1) ~= '@' then
    M.fail('package_path', 'cannot determine package path, source is not a file')
  end
  -- <root>/lua/picopack/utils.lua
  local root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(source:sub(2))))
  return M.normalize_path(root), vim.fs.basename(root)
end)()

---@param value any
---@param t type|"callable"
---@return boolean
local is_type = function(value, t)
  return type(value) == t or (t == 'callable' and vim.is_callable(value))
end

---@param validator vim.validate.Validator
---@return string
local expected_of = function(validator)
  if type(validator) == 'string' then
    return validator
  elseif type(validator) == 'table' and #validator > 0 then
    return table.concat(validator, ' or ')
  end
  return '?'
end

---@param name string
---@param value any
---@param validator vim.validate.Validator
---@param optional? boolean|string
---@param message? string
M.validate = function(name, value, validator, optional, message)
  local allow_nil = optional == true
  local msg = type(optional) == 'string' and optional or message
  if value == nil and allow_nil then
    return
  end

  local ok, info = false, nil
  if type(validator) == 'string' then
    ok = is_type(value, validator)
  elseif vim.is_callable(validator) then
    ok, info = validator(value)
  elseif type(validator) == 'table' then
    for _, t in ipairs(validator) do
      if is_type(value, t) then
        ok = true
        break
      end
    end
  else
    M.fail(name, 'invalid validator')
  end
  if ok then
    return
  end

  local err = ('expected %s, got %s'):format(msg or expected_of(validator), M.repr(value))
  M.fail(name, type(info) == 'string' and err .. '. Info: ' .. info or err)
end

---@param tbl table table to set value in
---@param value any value to set
---@param ... any keys to set
M.tbl_set = function(tbl, value, ...)
  M.validate('tbl', tbl, 'table')
  local keys = { ... }
  if #keys == 0 then
    M.fail('tbl_set', 'expected at least one key')
  end

  local parent = tbl
  for i = 1, #keys - 1 do
    local k = keys[i]
    local child = parent[k]
    if child == nil then
      child = {}
      parent[k] = child
    elseif type(child) ~= 'table' then
      M.fail('tbl_set', ('cannot set through non-table value at key %s'):format(M.repr(k)))
    end
    parent = child
  end
  parent[keys[#keys]] = value
end

---@generic T
---@param list T[]
---@param key? fun(item: T): any
---@return table<any, true>
M.list_to_set = function(list, key)
  local set = {}
  for _, item in ipairs(list) do
    local k = item
    if key then
      k = key(item)
    end
    set[k] = true
  end
  return set
end

---@generic T
---@param list T[]
---@param item T
---@param key? fun(item: T): any
M.list_insert_sorted = function(list, item, key)
  local idx = vim.list.bisect(list, item, { key = key, bound = 'upper' })
  table.insert(list, idx, item)
end

---@generic T
---@param list T[]
---@param key? fun(item: T): any
M.list_sort_stable = function(list, key)
  key = key or function(x) return x end
  local n = #list
  local decorated = {}
  for i = 1, n do
    local v = list[i]
    decorated[i] = { v = v, k = key(v), i = i }
  end
  table.sort(decorated, function(a, b)
    if a.k == b.k then
      return a.i < b.i
    end
    return a.k < b.k
  end)
  for i = 1, n do
    list[i] = decorated[i].v
  end
end

---@generic T
---@param list T[]
---@param key? fun(item: T): any
---@return T[]
M.list_filter_same = function(list, key)
  local seen = {}
  local result = {}
  for _, item in ipairs(list) do
    local k
    if key then
      k = key(item)
    else
      k = item
    end
    if not seen[k] then
      table.insert(result, item)
      seen[k] = true
    end
  end
  return result
end

return M
