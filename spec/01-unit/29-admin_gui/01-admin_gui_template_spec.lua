local helpers        = require "spec.helpers"
local admin_gui      = require "kong.admin_gui"
local conf_loader    = require "kong.conf_loader"
local prefix_handler = require "kong.cmd.utils.prefix_handler"

local exists = helpers.path.exists

describe("admin_gui template", function()
  local conf = assert(conf_loader(helpers.test_conf_path))

  it("auto-generates SSL certificate and key", function()
    assert(prefix_handler.gen_default_ssl_cert(conf, "admin_gui"))
    assert(exists(conf.admin_gui_ssl_cert_default))
    assert(exists(conf.admin_gui_ssl_cert_key_default))
  end)

  it("does not re-generate if they already exist", function()
    assert(prefix_handler.gen_default_ssl_cert(conf, "admin_gui"))
    local cer = helpers.file.read(conf.admin_gui_ssl_cert_default)
    local key = helpers.file.read(conf.admin_gui_ssl_cert_key_default)
    assert(prefix_handler.gen_default_ssl_cert(conf, "admin_gui"))
    assert.equal(cer, helpers.file.read(conf.admin_gui_ssl_cert_default))
    assert.equal(key, helpers.file.read(conf.admin_gui_ssl_cert_key_default))
  end)

  it("generates a different SSL certificate and key from the RESTful API", function()
    assert(prefix_handler.gen_default_ssl_cert(conf, "admin_gui"))
    local cer, key = {}, {}
    cer[1] = helpers.file.read(conf.admin_gui_ssl_cert_default)
    key[1] = helpers.file.read(conf.admin_gui_ssl_cert_key_default)
    assert(prefix_handler.gen_default_ssl_cert(conf, "admin"))
    cer[2] = helpers.file.read(conf.admin_ssl_cert_default)
    key[2] = helpers.file.read(conf.admin_ssl_cert_key_default)
    assert.not_equals(cer[1], cer[2])
    assert.not_equals(key[1], key[2])
  end)

  describe("admin_gui.generate_kconfig() - proxied", function()
    local conf = {
      admin_gui_url = "http://0.0.0.0:8002",
      admin_gui_api_url = "https://admin-reference.kong-cloud.com",
      proxy_url = "http://0.0.0.0:8000",
      admin_gui_listeners = {
        {
          ip = "0.0.0.0",
          port = 8002,
          ssl = false,
        },
        {
          ip = "0.0.0.0",
          port = 8445,
          ssl = true,
        },
      },
      admin_listeners = {
        {
          ip = "0.0.0.0",
          port = 8001,
          ssl = false,
        },
        {
          ip = "0.0.0.0",
          port = 8444,
          ssl = true,
        }
      },
      proxy_listeners = {
        {
          ip = "0.0.0.0",
          port = 8000,
          ssl = false,
        },
        {
          ip = "0.0.0.0",
          port = 8443,
          ssl = true,
        }
      },
      admin_gui_path = '/canopy'
    }

    it("should generates the appropriate kconfig", function()
      local kconfig_content = admin_gui.generate_kconfig(conf)

      assert.matches("'ADMIN_GUI_URL': 'http://0.0.0.0:8002'", kconfig_content, nil, true)
      assert.matches("'ADMIN_GUI_PATH': '/canopy'", kconfig_content, nil, true)
      assert.matches("'ADMIN_GUI_API_URL': 'https://admin-reference.kong-cloud.com'", kconfig_content, nil, true)
      assert.matches("'ADMIN_API_PORT': '8001'", kconfig_content, nil, true)
      assert.matches("'ADMIN_API_SSL_PORT': '8444'", kconfig_content, nil, true)
    end)

    it("should regenerates the appropriate kconfig from another call", function()
      local new_conf = conf

      -- change configuration values
      new_conf.admin_gui_url = 'http://admin-test.example.com'
      new_conf.admin_gui_path = '/canopy'
      new_conf.admin_gui_api_url = 'http://localhost:8001'
      new_conf.proxy_url = 'http://127.0.0.1:8000'

      -- regenerate kconfig
      local new_content = admin_gui.generate_kconfig(new_conf)

      -- test configuration values against template
      assert.matches("'ADMIN_GUI_URL': 'http://admin-test.example.com'", new_content, nil, true)
      assert.matches("'ADMIN_GUI_PATH': '/canopy'", new_content, nil, true)
      assert.matches("'ADMIN_GUI_API_URL': 'http://localhost:8001'", new_content, nil, true)
      assert.matches("'ADMIN_API_PORT': '8001'", new_content, nil, true)
      assert.matches("'ADMIN_API_SSL_PORT': '8444'", new_content, nil, true)
    end)
  end)

  describe("admin_gui.generate_kconfig() - not proxied", function()
    local conf = {
      admin_gui_url = "http://0.0.0.0:8002",
      proxy_url = "http://0.0.0.0:8000",
      admin_gui_api_url = "0.0.0.0:8001",
      anonymous_reports = false,
      admin_gui_listeners = {
        {
          ip = "0.0.0.0",
          port = 8002,
          ssl = false,
        },
        {
          ip = "0.0.0.0",
          port = 8445,
          ssl = true,
        },
      },
      admin_listeners = {
        {
          ip = "0.0.0.0",
          port = 8001,
          ssl = false,
        },
        {
          ip = "0.0.0.0",
          port = 8444,
          ssl = true,
        }
      },
      proxy_listeners = {
        {
          ip = "0.0.0.0",
          port = 8000,
          ssl = false,
        },
        {
          ip = "0.0.0.0",
          port = 8443,
          ssl = true,
        }
      },
      rbac = "off",
      rbac_auth_header = 'Kong-Admin-Token',
    }

    it("should generates the appropriate kconfig", function()
      local kconfig_content = admin_gui.generate_kconfig(conf)

      assert.matches("'ADMIN_GUI_URL': 'http://0.0.0.0:8002'", kconfig_content, nil, true)
      assert.matches("'ADMIN_GUI_API_URL': '0.0.0.0:8001'", kconfig_content, nil, true)
      assert.matches("'ADMIN_API_PORT': '8001'", kconfig_content, nil, true)
      assert.matches("'ADMIN_API_SSL_PORT': '8444'", kconfig_content, nil, true)
      assert.matches("'ANONYMOUS_REPORTS': 'false'", kconfig_content, nil, true)
    end)

    it("should regenerates the appropriate kconfig from another call", function()
      local new_conf = conf

      -- change configuration values
      new_conf.admin_gui_url = 'http://admin-test.example.com'
      new_conf.proxy_url = 'http://127.0.0.1:8000'
      new_conf.anonymous_reports = true

      -- regenerate kconfig
      local new_content = admin_gui.generate_kconfig(new_conf)

      -- test configuration values against template
      assert.matches("'ADMIN_GUI_URL': 'http://admin-test.example.com'", new_content, nil, true)
      assert.matches("'ADMIN_GUI_API_URL': '0.0.0.0:8001'", new_content, nil, true)
      assert.matches("'ADMIN_API_PORT': '8001'", new_content, nil, true)
      assert.matches("'ADMIN_API_SSL_PORT': '8444'", new_content, nil, true)
      assert.matches("'ANONYMOUS_REPORTS': 'true'", new_content, nil, true)
    end)
  end)
end)
