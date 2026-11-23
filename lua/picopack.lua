local Core = require('picopack.core')
local Utils = require('picopack.utils')

---@type PicoPack.Config
local config = {
  check_spec_unknown_keys = true,
}

local M = {}

M.url = {
  ---@param repo string
  ---@return string url
  gh = function(repo) return 'https://github.com/' .. repo end,
  ---@param repo string
  ---@return string url
  cb = function(repo) return 'https://codeberg.org/' .. repo end,
}

M.event = {
  ---@type PicoPack.Event
  VeryLazy = { name = 'User', pattern = 'VeryLazy' },
}

-- register api
M.is_registered = Utils.with_formatted_err(Core.is_registered)
M.registered = Utils.with_formatted_err(Core.registered)
M.register = Utils.with_formatted_err(
  ---@param spec PicoPack.Spec
  function(spec) Core.register(spec, config.check_spec_unknown_keys) end
)

-- load api
M.is_configured = Utils.with_formatted_err(Core.is_configured)
M.configured = Utils.with_formatted_err(Core.configured)
M.opts_extend = Utils.with_formatted_err(Core.opts_extend)
M.before_config = Utils.with_formatted_err(Core.before_config)
M.after_config = Utils.with_formatted_err(Core.after_config)
M.load_and_config = Utils.with_formatted_err(Core.load_and_config)

-- build api
M.is_pending_build = Utils.with_formatted_err(Core.is_pending_build)
M.pending_builds = Utils.with_formatted_err(Core.pending_builds)
M.build = Utils.with_formatted_err(Core.build)
M.build_pending = Utils.with_formatted_err(Core.build_pending)

-- status api
M.installed = Utils.with_formatted_err(Core.installed)
M.loaded = Utils.with_formatted_err(Core.loaded)
M.unmanaged = Utils.with_formatted_err(Core.unmanaged)
M.stats = Utils.with_formatted_err(Core.stats)

-- manage api
M.clean = Utils.with_formatted_err(Core.clean)
M.update = Utils.with_formatted_err(Core.update)
M.start = Utils.with_formatted_err(Core.start)

---@param opts PicoPack.Config
M.setup = Utils.with_formatted_err(function(opts)
  opts = opts or {}
  Utils.validate('opts.check_spec_unknown_keys', opts.check_spec_unknown_keys, 'boolean', true)
  config = vim.tbl_extend('force', config, opts)
end)

return M
