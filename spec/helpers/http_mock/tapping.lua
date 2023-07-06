--- Tapping implemented with http_mock
---@module spec.helpers.http_mock.tapping

local http_mock = require "spec.helpers.http_mock"

local tapping = {}

--- create a new tapping route.
-- @tparam string|number target the target host/port of the tapping route
-- @treturn table the tapping route
function tapping.new_tapping_route(target)
  if tonumber(target) then
    -- TODO: handle the resovler!
    target = "http://127.0.0.1:" .. target
  end

  if not target:find("://") then
    target = "http://" .. target
  end

  return {
    ["/"] = {
      directives = [[proxy_pass ]] .. target .. [[;]],
    }
  }
end

--- create a new http_mock.tapping instance with a tapping route.
-- @tparam string|number target the target host/port of the tapping route
-- @tparam[opt] table|string|number listens the listen directive of the mock server, defaults to a random available port
-- @tparam[opt="servroot_tapping"] string prefix the prefix of the mock server
-- @tparam[opt] table log_opts see `http_mock.new`
-- @treturn http_mock.tapping a tapping instance
-- @treturn number the port the mock server listens to
function tapping.new(target, listens, prefix, log_opts)
  ---@diagnostic disable-next-line: return-type-mismatch
  return http_mock.new(listens, tapping.new_tapping_route(target), {
    prefix = prefix or "servroot_tapping",
    log_opts = log_opts or {
      req = true,
      req_body = true,
      req_large_body = true,
    },
  })
end

return tapping
