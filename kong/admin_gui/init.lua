local pl_file  = require "pl.file"
local pl_utils = require "pl.utils"
local pl_path  = require "pl.path"

local log           = require "kong.cmd.utils.log"
local meta          = require "kong.meta"
local feature_flags = require "kong.admin_gui.feature_flags"
local hooks         = require "kong.hooks"
local api_helpers   = require "kong.admin_gui.api_helpers"

local _M = {}


function _M.feature_flags_init(config)
  if config and config.feature_conf_path and config.feature_conf_path ~= "" then
    local _, err = feature_flags.init(config.feature_conf_path)
    if err then
      return err
    end
  end
end

local function write_kconfig(configs, filename)
  local kconfig_str = "window.K_CONFIG = {\n"
  for config, value in pairs(configs) do
    kconfig_str = kconfig_str .. "  '" .. config .. "': '" .. value .. "',\n"
  end

  -- remove trailing comma
  kconfig_str = kconfig_str:sub(1, -3)

  if not pl_file.write(filename, kconfig_str .. "\n}\n") then
    log.warn("Could not write file " .. filename .. ". Ensure that the Kong " ..
      "CLI user has permissions to write to this directory")
  end
end

local function prepare_interface(usr_path, interface_dir, interface_conf_dir, interface_env, kong_config)
  local usr_interface_path = usr_path .. "/" .. interface_dir
  local interface_path = kong_config.prefix .. "/" .. interface_dir
  local interface_conf_path = kong_config.prefix .. "/" .. interface_conf_dir
  local compile_env = interface_env
  local config_filename = interface_conf_path .. "/kconfig.js"

  if not pl_path.exists(interface_conf_path) then
    if not pl_path.mkdir(interface_conf_path) then
      log.warn("Could not create directory " .. interface_conf_path .. ". " ..
        "Ensure that the Kong CLI user has permissions to create " ..
        "this directory.")
    end
  end

  -- if the interface directory is not exist in custom prefix directory
  -- try symlinking to the default prefix location
  -- ensure user can access the interface appliation
  if not pl_path.exists(interface_path)
      and pl_path.exists(usr_interface_path) then

    local ln_cmd = "ln -s " .. usr_interface_path .. " " .. interface_path
    local ok, _, _, err_t = pl_utils.executeex(ln_cmd)

    if not ok then
      log.warn(err_t)
    end
  end

  write_kconfig(compile_env, config_filename)
end

_M.prepare_interface = prepare_interface

-- return first listener matching filters
local function select_listener(listeners, filters)
  for _, listener in ipairs(listeners) do
    local match = true
    for filter, value in pairs(filters) do
      if listener[filter] ~= value then
        match = false
      end
    end
    if match then
      return listener
    end
  end
end

local function prepare_variable(variable)
  if variable == nil then
    return ""
  end

  return tostring(variable)
end

function _M.prepare_admin(kong_config)
  local gui_listen = select_listener(kong_config.admin_gui_listeners, { ssl = false })
  local gui_port = gui_listen and gui_listen.port
  local gui_ssl_listen = select_listener(kong_config.admin_gui_listeners, { ssl = true })
  local gui_ssl_port = gui_ssl_listen and gui_ssl_listen.port

  local api_url
  local api_listen
  local api_port
  local api_ssl_listen
  local api_ssl_port

  -- only access the admin API on the proxy if auth is enabled
  api_listen = select_listener(kong_config.admin_listeners, { ssl = false })
  api_port = api_listen and api_listen.port
  api_ssl_listen = select_listener(kong_config.admin_listeners, { ssl = true })
  api_ssl_port = api_ssl_listen and api_ssl_listen.port
  -- TODO: stop using this property, and introduce admin_api_url so that
  -- api_url always includes the protocol
  api_url = kong_config.admin_api_uri

  return prepare_interface("/usr/local/kong", "gui", "gui_config", {
    ADMIN_GUI_AUTH = prepare_variable(kong_config.admin_gui_auth),
    ADMIN_GUI_URL = prepare_variable(kong_config.admin_gui_url),
    ADMIN_GUI_PATH = prepare_variable(kong_config.admin_gui_path),
    ADMIN_GUI_PORT = prepare_variable(gui_port),
    ADMIN_GUI_SSL_PORT = prepare_variable(gui_ssl_port),
    ADMIN_API_URL = prepare_variable(api_url),
    ADMIN_API_PORT = prepare_variable(api_port),
    ADMIN_API_SSL_PORT = prepare_variable(api_ssl_port),
    ADMIN_GUI_HEADER_TXT = prepare_variable(kong_config.admin_gui_header_txt),
    ADMIN_GUI_HEADER_BG_COLOR = prepare_variable(kong_config.admin_gui_header_bg_color),
    ADMIN_GUI_HEADER_TXT_COLOR = prepare_variable(kong_config.admin_gui_header_txt_color),
    ADMIN_GUI_FOOTER_TXT = prepare_variable(kong_config.admin_gui_footer_txt),
    ADMIN_GUI_FOOTER_BG_COLOR = prepare_variable(kong_config.admin_gui_footer_bg_color),
    ADMIN_GUI_FOOTER_TXT_COLOR = prepare_variable(kong_config.admin_gui_footer_txt_color),
    ADMIN_GUI_LOGIN_BANNER_TITLE = prepare_variable(kong_config.admin_gui_login_banner_title),
    ADMIN_GUI_LOGIN_BANNER_BODY = prepare_variable(kong_config.admin_gui_login_banner_body),
    KONG_VERSION = prepare_variable(meta.version),
    FEATURE_FLAGS = prepare_variable(kong_config.admin_gui_flags),
    ANONYMOUS_REPORTS = prepare_variable(kong_config.anonymous_reports),
  }, kong_config)
end

function _M.init()
  if kong.configuration.admin_gui_listeners then
    _M.prepare_admin(kong.configuration)
  end

  hooks.register_hook("api:init:pre", function(app)
    app:before_filter(api_helpers.before_filter)

    return true
  end)
end

return _M
