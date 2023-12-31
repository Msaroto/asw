local url = require "socket.url"
local typedefs = require "kong.db.schema.typedefs"
local secret = require "kong.plugins.oauth2.secret"


local assert = assert


local function validate_uri(uri)
  local parsed_uri = url.parse(uri)
  if not (parsed_uri and parsed_uri.host and parsed_uri.scheme) then
    return nil, "cannot parse '" .. uri .. "'"
  end
  if parsed_uri.fragment ~= nil then
    return nil, "fragment not allowed in '" .. uri .. "'"
  end

  return true
end


local oauth2_credentials = {
  primary_key = { "id" },
  name = "oauth2_credentials",
  cache_key = { "client_id" },
  endpoint_key = "client_id",
  workspaceable = true,
  admin_api_name = "oauth2",
  fields = {
    { id = typedefs.uuid },
    { created_at = typedefs.auto_timestamp_s },
    { consumer = { type = "foreign", reference = "consumers", required = true, on_delete = "cascade", }, },
    { name = { type = "string", required = true }, },
    { client_id = { type = "string", required = false, unique = true, auto = true }, },
    { client_secret = { type = "string", required = false, auto = true, encrypted = true }, }, -- encrypted = true is a Kong Enterprise Exclusive feature. It does nothing in Kong CE
    { hash_secret = { type = "boolean", required = true, default = false }, },
    { redirect_uris = {
      type = "array",
      required = false,
      elements = {
        type = "string",
        custom_validator = validate_uri,
    }, }, },
    { tags = typedefs.tags },
    { client_type = { type = "string", required = true, default = "confidential", one_of = { "confidential", "public" }, }, },
  },
  transformations = {
    {
      input = { "hash_secret" },
      needs = { "client_secret" },
      on_write = function(hash_secret, client_secret)
        if not hash_secret then
          return {}
        end
        local hash = assert(secret.hash(client_secret))
        return {
          client_secret = hash,
        }
      end,
    },
  },
}


local oauth2_authorization_codes = {
  primary_key = { "id" },
  name = "oauth2_authorization_codes",
  ttl = true,
  workspaceable = true,
  generate_admin_api = false,
  db_export = false,
  fields = {
    { id = typedefs.uuid },
    { created_at = typedefs.auto_timestamp_s },
    { service = { type = "foreign", reference = "services", default = ngx.null, on_delete = "cascade", }, },
    { credential = { type = "foreign", reference = "oauth2_credentials", required = true, on_delete = "cascade", }, },
    { code = { type = "string", required = false, unique = true, auto = true }, }, -- FIXME immutable
    { authenticated_userid = { type = "string", required = false }, },
    { scope = { type = "string" }, },
    { challenge = { type = "string", required = false }},
    { challenge_method = { type = "string", required = false, one_of = { "S256" } }},
    { plugin = { type = "foreign", reference = "plugins", default = ngx.null, on_delete = "cascade", }, },
  },
}


local BEARER = "bearer"
local oauth2_tokens = {
  primary_key = { "id" },
  name = "oauth2_tokens",
  endpoint_key = "access_token",
  cache_key = { "access_token" },
  dao = "kong.plugins.oauth2.daos.oauth2_tokens",
  ttl = true,
  workspaceable = true,
  fields = {
    { id = typedefs.uuid },
    { created_at = typedefs.auto_timestamp_s },
    { service = { type = "foreign", reference = "services", default = ngx.null, on_delete = "cascade", }, },
    { credential = { type = "foreign", reference = "oauth2_credentials", required = true, on_delete = "cascade", }, },
    { token_type = { type = "string", required = true, one_of = { BEARER }, default = BEARER }, },
    { expires_in = { type = "integer", required = true }, },
    { access_token = { type = "string", required = false, unique = true, auto = true }, },
    { refresh_token = { type = "string", required = false, unique = true }, },
    { authenticated_userid = { type = "string", required = false }, },
    { scope = { type = "string" }, },
  },
}


return {
  oauth2_credentials,
  oauth2_authorization_codes,
  oauth2_tokens,
}
