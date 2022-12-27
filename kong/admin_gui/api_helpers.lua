local app_helpers = require "lapis.application"

local utils = require "kong.tools.utils"

local _M = {}

_M.apis = {
  ADMIN = "admin",
}

function _M.before_filter()
  local req_id = utils.random_string()
  local invoke_plugin = kong.invoke_plugin

  ngx.ctx.admin_api = {
    req_id = req_id,
  }
  ngx.header["X-Kong-Admin-Request-ID"] = req_id

  do
    -- in case of endpoint with missing `/`, this block is executed twice.
    -- So previous workspace should be dropped
    ngx.ctx.admin_api_request = true

    local origin = kong.configuration.admin_gui_origin or "*"

    local cors_conf = {
      origins = { origin },
      methods = { "GET", "PUT", "PATCH", "DELETE", "POST" },
      credentials = true,
    }

    local ok, err = invoke_plugin({
      name = "cors",
      config = cors_conf,
      phases = { "access", "header_filter" },
      api_type = _M.apis.ADMIN,
      db = kong.db,
    })

    if not ok then
      return app_helpers.yield_error(err)
    end
  end
end

return _M
