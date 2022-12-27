local listeners = require "kong.conf_loader.listeners"
local log = require "kong.cmd.utils.log"
local try_decode_base64 = require "kong.tools.utils".try_decode_base64

local pl_stringx = require "pl.stringx"
local pl_path = require "pl.path"
local pl_file = require "pl.file"
local cjson = require "cjson.safe"
local openssl_x509 = require "resty.openssl.x509"
local openssl_pkey = require "resty.openssl.pkey"
local url = require "socket.url"

local concat = table.concat


local ADMIN_GUI_PREFIX_PATHS = {
  nginx_kong_gui_include_conf = { "nginx-kong-gui-include.conf" },
  admin_gui_ssl_cert_default = { "ssl", "admin-gui-kong-default.crt" },
  admin_gui_ssl_cert_key_default = { "ssl", "admin-gui-kong-default.key" },
  admin_gui_ssl_cert_default_ecdsa = { "ssl", "admin-gui-kong-default-ecdsa.crt" },
  admin_gui_ssl_cert_key_default_ecdsa = { "ssl", "admin-gui-kong-default-ecdsa.key" },
}


local ADMIN_GUI_CONF_INFERENCES = {
  admin_api_uri = { typ = "string" },
  admin_gui_listen = { typ = "array" },
  admin_gui_path = { typ = "string" },
  admin_gui_error_log = { typ = "string" },
  admin_gui_access_log = { typ = "string" },
  admin_gui_flags = { typ = "string" },
  admin_gui_auth = { typ = "string" },
  admin_gui_auth_conf = { typ = "string" },
  admin_gui_auth_header = { typ = "string" },
  admin_gui_auth_password_complexity = { typ = "string" },
  admin_gui_session_conf = { typ = "string" },
  admin_gui_auth_login_attempts = { typ = "number" },
  admin_emails_from = { typ = "string" },
  admin_emails_reply_to = { typ = "string" },
  admin_invitation_expiry = { typ = "number" },
  admin_gui_ssl_cert = { typ = "array" },
  admin_gui_ssl_cert_key = { typ = "array" },

  admin_gui_header_txt = { typ = "string" },
  admin_gui_header_bg_color = { typ = "string" },
  admin_gui_header_txt_color = { typ = "string" },

  admin_gui_footer_txt = { typ = "string" },
  admin_gui_footer_bg_color = { typ = "string" },
  admin_gui_footer_txt_color = { typ = "string" },

  admin_gui_login_banner_title = { typ = "string" },
  admin_gui_login_banner_body = { typ = "string" },
}


local ADMIN_GUI_CONF_SENSITIVE = {
  admin_gui_auth_header = true,
  admin_gui_auth_conf = true,
  admin_gui_session_conf = true,
}

local function validate_admin_gui_path(conf, errors)
  if conf.admin_gui_path then
    if not conf.admin_gui_path:find("^/") then
      errors[#errors + 1] = "admin_gui_path must start with a slash ('/')"
    end
    if conf.admin_gui_path:find("^/.+/$") then
      errors[#errors + 1] = "admin_gui_path must not end with a slash ('/')"
    end
    if conf.admin_gui_path:match("[^%a%d%-_/]+") then
      errors[#errors + 1] = "admin_gui_path can only contain letters, digits, " ..
          "hyphens ('-'), underscores ('_'), and slashes ('/')"
    end
    if conf.admin_gui_path:match("//+") then
      errors[#errors + 1] = "admin_gui_path must not contain continuous slashes ('/')"
    end
  end
end

local function validate_admin_gui_authentication(conf, errors)
  -- TODO: reinstate validation after testing all auth types
  if conf.admin_gui_auth then
    if conf.admin_gui_auth ~= "key-auth" and
        conf.admin_gui_auth ~= "basic-auth" and
        conf.admin_gui_auth ~= "ldap-auth-advanced" and
        conf.admin_gui_auth ~= "openid-connect" then
      errors[#errors + 1] = "admin_gui_auth must be 'key-auth', 'basic-auth', " ..
          "'ldap-auth-advanced', 'openid-connect' or not set"
    end

    if not conf.enforce_rbac or conf.enforce_rbac == 'off' then
      errors[#errors + 1] = "enforce_rbac must be enabled when " ..
          "admin_gui_auth is enabled"
    end
  end

  if conf.admin_gui_auth_conf and conf.admin_gui_auth_conf ~= "" then
    if not conf.admin_gui_auth or conf.admin_gui_auth == "" then
      errors[#errors + 1] = "admin_gui_auth_conf is set with no admin_gui_auth"
    end

    local auth_config, err = cjson.decode(tostring(conf.admin_gui_auth_conf))
    if err then
      errors[#errors + 1] = "admin_gui_auth_conf must be valid json or not set: "
          .. err .. " - " .. conf.admin_gui_auth_conf
    else
      -- validate admin_gui_auth_conf for OIDC Auth
      if conf.admin_gui_auth == "openid-connect" then

        if not auth_config.admin_claim then
          errors[#errors + 1] = "admin_gui_auth_conf must contains 'admin_claim' "
              .. "when admin_gui_auth='openid-connect'"
        end

        -- admin_claim type checking
        if auth_config.admin_claim and type(auth_config.admin_claim) ~= "string" then
          errors[#errors + 1] = "admin_claim must be a string"
        end

        -- only allow customers to map admin with 'username' temporary
        -- also ensured admin_by is a string value
        if auth_config.admin_by and auth_config.admin_by ~= "username" then
          errors[#errors + 1] = "admin_by only supports value with 'username'"
        end

        -- only allow customers to specify 1 claim to map with rbac roles
        if auth_config.authenticated_groups_claim and
            #auth_config.authenticated_groups_claim > 1
        then
          errors[#errors + 1] = "authenticated_groups_claim only supports 1 claim"
        end

        -- admin_auto_create_rbac_token_disabled type checking
        if auth_config.admin_auto_create_rbac_token_disabled and
            type(auth_config.admin_auto_create_rbac_token_disabled) ~= "boolean"
        then
          errors[#errors + 1] = "admin_auto_create_rbac_token_disabled must be a boolean"
        end

      end

      conf.admin_gui_auth_conf = auth_config

      -- used for writing back to prefix/.kong_env
      setmetatable(conf.admin_gui_auth_conf, {
        __tostring = function(v)
          return assert(cjson.encode(v))
        end
      })
    end
  end

  local keyword = "admin_gui_auth_password_complexity"
  if conf[keyword] and conf[keyword] ~= "" then
    if not conf.admin_gui_auth or conf.admin_gui_auth ~= "basic-auth" then
      errors[#errors + 1] = keyword .. " is set without basic-auth"
    end

    local auth_password_complexity, err = cjson.decode(tostring(conf[keyword]))
    if err then
      errors[#errors + 1] = keyword .. " must be valid json or not set: "
          .. err .. " - " .. conf[keyword]
    else
      -- convert json to lua table format
      conf[keyword] = auth_password_complexity

      setmetatable(conf[keyword], {
        __tostring = function(v)
          return assert(cjson.encode(v))
        end
      })
    end
  end
end

local function validate_admin_gui_session(conf, errors)
  if conf.admin_gui_session_conf then
    if not conf.admin_gui_auth or conf.admin_gui_auth == "" then
      errors[#errors + 1] = "admin_gui_session_conf is set with no admin_gui_auth"
    end

    local session_config, err = cjson.decode(tostring(conf.admin_gui_session_conf))
    if err then
      errors[#errors + 1] = "admin_gui_session_conf must be valid json or not set: "
          .. err .. " - " .. conf.admin_gui_session_conf
    else
      -- apply default session storage "kong"
      if not session_config.storage or session_config.storage == "" then
        session_config.storage = "kong"
      end

      conf.admin_gui_session_conf = session_config

      -- used for writing back to prefix/.kong_env
      setmetatable(conf.admin_gui_session_conf, {
        __tostring = function(v)
          return assert(cjson.encode(v))
        end
      })
    end
  elseif conf.admin_gui_auth or conf.admin_gui_auth == "" then
    errors[#errors + 1] =
    "admin_gui_session_conf must be set when admin_gui_auth is enabled"
  end
end

local function validate_ssl(prefix, conf, errors)
  local listen = conf[prefix .. "listen"]

  local ssl_enabled = (concat(listen, ",") .. " "):find("%sssl[%s,]") ~= nil
  if not ssl_enabled and prefix == "proxy_" then
    ssl_enabled = (concat(conf.stream_listen, ",") .. " "):find("%sssl[%s,]") ~= nil
  end

  if ssl_enabled then
    conf.ssl_enabled = true

    local ssl_cert = conf[prefix .. "ssl_cert"]
    local ssl_cert_key = conf[prefix .. "ssl_cert_key"]

    if #ssl_cert > 0 and #ssl_cert_key == 0 then
      errors[#errors + 1] = prefix .. "ssl_cert_key must be specified"

    elseif #ssl_cert_key > 0 and #ssl_cert == 0 then
      errors[#errors + 1] = prefix .. "ssl_cert must be specified"

    elseif #ssl_cert ~= #ssl_cert_key then
      errors[#errors + 1] = prefix .. "ssl_cert was specified " .. #ssl_cert .. " times while " ..
          prefix .. "ssl_cert_key was specified " .. #ssl_cert_key .. " times"
    end

    if ssl_cert then
      for i, cert in ipairs(ssl_cert) do
        if not pl_path.exists(cert) then
          cert = try_decode_base64(cert)
          ssl_cert[i] = cert
          local _, err = openssl_x509.new(cert)
          if err then
            errors[#errors + 1] = prefix .. "ssl_cert: failed loading certificate from " .. cert
          end
        end
      end
      conf[prefix .. "ssl_cert"] = ssl_cert
    end

    if ssl_cert_key then
      for i, cert_key in ipairs(ssl_cert_key) do
        if not pl_path.exists(cert_key) then
          cert_key = try_decode_base64(cert_key)
          ssl_cert_key[i] = cert_key
          local _, err = openssl_pkey.new(cert_key)
          if err then
            errors[#errors + 1] = prefix .. "ssl_cert_key: failed loading key from " .. cert_key
          end
        end
      end
      conf[prefix .. "ssl_cert_key"] = ssl_cert_key
    end
  end
end

local function validate_admin_gui_ssl(conf, errors)
  validate_ssl("admin_gui_", conf, errors)
end

local function validate(conf, errors)
  validate_admin_gui_path(conf, errors)
  validate_admin_gui_authentication(conf, errors)
  validate_admin_gui_ssl(conf, errors)
  validate_admin_gui_session(conf, errors)

  if conf.audit_log_signing_key then
    local k = pl_path.abspath(conf.audit_log_signing_key)

    local p, err = openssl_pkey.new(pl_file.read(k), {
      format = "PEM",
      type = "pr",
    })
    if not p then
      errors[#errors + 1] = "audit_log_signing_key: invalid RSA private key ("
          .. err .. ")"
    end

    conf.audit_log_signing_key = k
  end


  -- warn user if admin_gui_auth is on but admin_gui_url is empty
  if conf.admin_gui_auth and not conf.admin_gui_url then
    log.warn("when admin_gui_auth is set, admin_gui_url is required")
  end

  if conf.role == "control_plane" then
    if #conf.cluster_telemetry_listen < 1 or pl_stringx.strip(conf.cluster_telemetry_listen[1]) == "off" then
      errors[#errors + 1] = "cluster_telemetry_listen must be specified when role = \"control_plane\""
    end
  end
end

local function load_ssl_cert_abs_paths(prefix, conf)
  local ssl_cert = conf[prefix .. "_cert"]
  local ssl_cert_key = conf[prefix .. "_cert_key"]

  if ssl_cert and ssl_cert_key then
    if type(ssl_cert) == "table" then
      for i, cert in ipairs(ssl_cert) do
        if pl_path.exists(cert) then
          ssl_cert[i] = pl_path.abspath(cert)
        end
      end

    elseif pl_path.exists(ssl_cert) then
      conf[prefix .. "_cert"] = pl_path.abspath(ssl_cert)
    end

    if type(ssl_cert_key) == "table" then
      for i, key in ipairs(ssl_cert_key) do
        if pl_path.exists(key) then
          ssl_cert_key[i] = pl_path.abspath(key)
        end
      end

    elseif pl_path.exists(ssl_cert_key) then
      conf[prefix .. "_cert_key"] = pl_path.abspath(ssl_cert_key)
    end
  end
end

local function load(conf)
  -- admin_gui_origin is a parameter for internal use only
  -- it's not set directly by the user
  -- if admin_gui_path is set to a path other than /, admin_gui_url may
  -- contain a path component
  -- to make it suitable to be used as an origin in headers, we need to
  -- parse and reconstruct the admin_gui_url to ensure it only contains
  -- the scheme, host, and port
  if conf.admin_gui_url then
    local parsed_url = url.parse(conf.admin_gui_url)
    conf.admin_gui_origin = parsed_url.scheme .. "://" .. parsed_url.authority
  end

  local ok, err = listeners.parse(conf, {
    { name = "admin_gui_listen", subsystem = "http", ssl_flag = "admin_gui_ssl_enabled" },
  })
  if not ok then
    return false, err
  end

  load_ssl_cert_abs_paths("admin_gui_ssl", conf)

  return true
end

local function add(dst, src)
  for k, v in pairs(src) do
    dst[k] = v
  end
end

return {
  ADMIN_GUI_PREFIX_PATHS = ADMIN_GUI_PREFIX_PATHS,
  ADMIN_GUI_CONF_INFERENCES = ADMIN_GUI_CONF_INFERENCES,
  ADMIN_GUI_CONF_SENSITIVE = ADMIN_GUI_CONF_SENSITIVE,

  validate = validate,
  load = load,
  add = add,

  -- only exposed for unit testing :-(
  validate_admin_gui_path = validate_admin_gui_path,
  validate_admin_gui_authentication = validate_admin_gui_authentication,
  validate_admin_gui_session = validate_admin_gui_session,
  validate_admin_gui_ssl = validate_admin_gui_ssl,
}
