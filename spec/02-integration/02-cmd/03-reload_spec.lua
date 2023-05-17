local helpers = require "spec.helpers"
local cjson = require "cjson"


local wait_for_file_contents = helpers.wait_for_file_contents

local function try_connect(port)
  local sock, err = ngx.socket.tcp()
  if not sock then
    return nil, err or "unknown error"
  end

  sock:settimeouts(100, 100, 100)

  local ok
  ok, err = sock:connect("127.0.0.1", port)

  sock:close()

  if ok then
    return true
  end

  return false, err or "unknown error"
end

local function assert_connect(port, when, timeout)
  timeout = timeout or 5

  local msg = "failed to connect to port " .. port .. " " .. when

  assert
    .with_timeout(timeout)
    .eventually(function()
      return try_connect(port)
    end)
    .is_truthy(msg)
end

local function assert_not_connect(port, when, timeout)
  timeout = timeout or 5

  local msg = "expected connection to port " .. port ..  " to fail "
              .. "with 'connection refused' " .. when

  assert
    .with_timeout(timeout)
    .eventually(function()
      local ok, err = try_connect(port)
      if ok then
        return false, "connection succeeded"

      elseif err ~= "connection refused" then
        return false, "unexpected error: " .. tostring(err)
      end

      return true
    end)
    .is_truthy(msg)
end


for _, strategy in helpers.each_strategy() do

describe("kong reload #" .. strategy, function()
  lazy_setup(function()
    helpers.get_db_utils(nil, {}) -- runs migrations
    helpers.prepare_prefix()
  end)

  lazy_teardown(function()
    helpers.clean_prefix()
  end)

  after_each(function()
    helpers.stop_kong()
  end)

  it("send a 'reload' signal to a running Nginx master process", function()
    assert(helpers.start_kong())

    local nginx_pid = wait_for_file_contents(helpers.test_conf.nginx_pid, 10)

    -- kong_exec uses test conf too, so same prefix
    assert(helpers.reload_kong(strategy, "reload --prefix " .. helpers.test_conf.prefix))

    local nginx_pid_after = wait_for_file_contents(helpers.test_conf.nginx_pid, 10)

    -- same master PID
    assert.equal(nginx_pid, nginx_pid_after)
  end)

  it("reloads from a --conf argument", function()
    assert_not_connect(9002, "before starting kong")

    assert(helpers.start_kong({
      proxy_listen = "0.0.0.0:9002"
    }, nil, true))

    assert_connect(9002, "after starting kong")
    assert_not_connect(9002, "after staring kong (but before reloading)")

    local nginx_pid = assert(helpers.file.read(helpers.test_conf.nginx_pid),
                             "no nginx master PID")

    assert(helpers.kong_exec("reload --conf spec/fixtures/reload.conf"))

    assert_connect(9000, "after reloading kong")
    assert_not_connect(9002, "after reloading kong")

    -- same master PID
    assert.equal(nginx_pid, helpers.file.read(helpers.test_conf.nginx_pid))
  end)

  it("reloads from environment variables", function()
    assert_not_connect(9002, "before starting kong")

    assert(helpers.start_kong({
      proxy_listen = "0.0.0.0:9002"
    }, nil, true))

    assert_connect(9002, "after starting kong")
    assert_not_connect(9000, "after staring kong (but before reloading")

    local nginx_pid = assert(helpers.file.read(helpers.test_conf.nginx_pid),
                             "no nginx master PID")

    assert(helpers.kong_exec("reload --conf " .. helpers.test_conf_path, {
      proxy_listen = "0.0.0.0:9000"
    }))

    assert_connect(9000, "after reloading kong")
    assert_not_connect(9002, "after reloading kong")

    -- same master PID
    assert.equal(nginx_pid, helpers.file.read(helpers.test_conf.nginx_pid))
  end)

  it("accepts a custom nginx template", function()
    assert_not_connect(9002, "before starting kong")

    assert(helpers.start_kong({
      proxy_listen = "0.0.0.0:9002"
    }, nil, true))

    assert_connect(9002, "after starting kong")
    assert_not_connect(helpers.mock_upstream_port, "after starting kong "
                       .. "(but before reloading)")

    assert(helpers.kong_exec("reload --conf " .. helpers.test_conf_path
           .. " --nginx-conf spec/fixtures/custom_nginx.template"))

    assert_connect(helpers.mock_upstream_port, "after reloading kong")
  end)

  it("clears the 'kong' shm", function()
    assert(helpers.start_kong())

    client = helpers.admin_client()
    local res = assert(client:get("/"))
    local body = assert.res_status(200, res)
    local json = cjson.decode(body)
    local pids_1 = json.pids
    client:close()

    assert(helpers.reload_kong(strategy, "reload --prefix " .. helpers.test_conf.prefix))

    client = helpers.admin_client()
    local res = assert(client:get("/"))
    local body = assert.res_status(200, res)
    local json = cjson.decode(body)
    local pids_2 = json.pids
    client:close()

    assert.equal(pids_2.master, pids_1.master)

    for _, v in ipairs(pids_2.workers) do
      for _, v_old in ipairs(pids_1.workers) do
        assert.not_equal(v, v_old)
      end
    end
  end)

  it("clears the 'kong' shm but preserves 'node_id'", function()
    assert(helpers.start_kong())

    client = helpers.admin_client()
    local res = assert(client:get("/"))
    local body = assert.res_status(200, res)
    local json = cjson.decode(body)
    local node_id_1 = json.node_id
    client:close()

    assert(helpers.reload_kong(strategy, "reload --prefix " .. helpers.test_conf.prefix))

    client = helpers.admin_client()
    local res = assert(client:get("/"))
    local body = assert.res_status(200, res)
    local json = cjson.decode(body)
    local node_id_2 = json.node_id
    client:close()

    assert.equal(node_id_1, node_id_2)
  end)

  if strategy == "off" then
    it("reloads the declarative_config from kong.conf", function()
      local yaml_file = helpers.make_yaml_file [[
        _format_version: "1.1"
        services:
        - name: my-service
          url: http://127.0.0.1:15555
          routes:
          - name: example-route
            hosts:
            - example.test
      ]]

      local pok, admin_client

      finally(function()
        os.remove(yaml_file)
      end)

      assert(helpers.start_kong({
        database = "off",
        declarative_config = yaml_file,
        nginx_worker_processes = 1,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      helpers.wait_until(function()
        pok, admin_client = pcall(helpers.admin_client)
        if not pok then
          return false
        end

        local res = assert(admin_client:send {
          method = "GET",
          path = "/services",
        })
        assert.res_status(200, res)

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.same(1, #json.data)
        assert.same(ngx.null, json.next)

        admin_client:close()

        return "my-service" == json.data[1].name
      end, 10)

      -- rewrite YAML file
      helpers.make_yaml_file([[
        _format_version: "1.1"
        services:
        - name: mi-servicio
          url: http://127.0.0.1:15555
          routes:
          - name: example-route
            hosts:
            - example.test
      ]], yaml_file)

      assert(helpers.reload_kong(strategy, "reload --prefix " .. helpers.test_conf.prefix, {
        declarative_config = yaml_file,
      }))

      helpers.wait_until(function()
        pok, admin_client = pcall(helpers.admin_client)
        if not pok then
          return false
        end
        local res = assert(admin_client:send {
          method = "GET",
          path = "/services",
        })
        assert.res_status(200, res)

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.same(1, #json.data)
        assert.same(ngx.null, json.next)
        admin_client:close()

        return "mi-servicio" == json.data[1].name
      end)
    end)

    it("preserves declarative config from memory when not using declarative_config from kong.conf", function()
      local pok, admin_client

      assert(helpers.start_kong({
        database = "off",
        nginx_worker_processes = 1,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      helpers.wait_until(function()
        pok, admin_client = pcall(helpers.admin_client)
        if not pok then
          return false
        end

        local res = assert(admin_client:send {
          method = "POST",
          path = "/config",
          headers = {
            ["Content-Type"] = "application/json",
          },
          body = {
            _format_version = "1.1",
            services = {
              {
                name = "my-service",
                url = "http://127.0.0.1:15555",
              }
            }
          },
        }, 10)
        assert.res_status(201, res)

        admin_client:close()

        return true
      end)

      assert(helpers.reload_kong(strategy, "reload --prefix " .. helpers.test_conf.prefix))

      admin_client = assert(helpers.admin_client())
      local res = assert(admin_client:send {
        method = "GET",
        path = "/services",
      })
      assert.res_status(200, res)

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same(1, #json.data)
      assert.same(ngx.null, json.next)
      admin_client:close()

      return "my-service" == json.data[1].name
    end)

    it("preserves declarative config from memory even when kong was started with a declarative_config", function()
      local yaml_file = helpers.make_yaml_file [[
        _format_version: "1.1"
        services:
        - name: my-service-on-start
          url: http://127.0.0.1:15555
          routes:
          - name: example-route
            hosts:
            - example.test
      ]]

      local pok, admin_client

      assert(helpers.start_kong({
        database = "off",
        nginx_worker_processes = 1,
        declarative_config = yaml_file,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      helpers.wait_until(function()
        pok, admin_client = pcall(helpers.admin_client)
        if not pok then
          return false
        end

        local res = assert(admin_client:send {
          method = "GET",
          path = "/services",
        })
        assert.res_status(200, res)

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.same(1, #json.data)
        assert.same(ngx.null, json.next)

        admin_client:close()

        return "my-service-on-start" == json.data[1].name
      end, 10)

      helpers.wait_until(function()
        pok, admin_client = pcall(helpers.admin_client)
        if not pok then
          return false
        end

        local res = assert(admin_client:send {
          method = "POST",
          path = "/config",
          headers = {
            ["Content-Type"] = "application/json",
          },
          body = {
            _format_version = "1.1",
            services = {
              {
                name = "my-service",
                url = "http://127.0.0.1:15555",
              }
            }
          },
        }, 10)
        assert.res_status(201, res)

        admin_client:close()

        return true
      end)

      assert(helpers.reload_kong(strategy, "reload --prefix " .. helpers.test_conf.prefix))

      admin_client = assert(helpers.admin_client())
      local res = assert(admin_client:send {
        method = "GET",
        path = "/services",
      })
      assert.res_status(200, res)

      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same(1, #json.data)
      assert.same(ngx.null, json.next)
      admin_client:close()

      return "my-service" == json.data[1].name
    end)

    it("change target loaded from declarative_config", function()
      local yaml_file = helpers.make_yaml_file [[
        _format_version: "1.1"
        services:
        - name: my-service
          url: http://127.0.0.1:15555
          routes:
          - name: example-route
            hosts:
            - example.test
        upstreams:
        - name: my-upstream
          targets:
          - target: 127.0.0.1:15555
            weight: 100
      ]]

      local pok, admin_client

      finally(function()
        os.remove(yaml_file)
      end)

      assert(helpers.start_kong({
        database = "off",
        declarative_config = yaml_file,
        nginx_worker_processes = 1,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      helpers.wait_until(function()
        pok, admin_client = pcall(helpers.admin_client)
        if not pok then
          return false
        end

        local res = assert(admin_client:send {
          method = "GET",
          path = "/services",
        })
        assert.res_status(200, res)

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.same(1, #json.data)
        assert.same(ngx.null, json.next)

        admin_client:close()

        return "my-service" == json.data[1].name
      end, 10)

      -- rewrite YAML file
      helpers.make_yaml_file([[
        _format_version: "1.1"
        services:
        - name: my-service
          url: http://127.0.0.1:15555
          routes:
          - name: example-route
            hosts:
            - example.test
        upstreams:
        - name: my-upstream
          targets:
          - target: 127.0.0.1:15556
            weight: 100
      ]], yaml_file)

      assert(helpers.reload_kong(strategy, "reload --prefix " .. helpers.test_conf.prefix, {
        declarative_config = yaml_file,
      }))

      helpers.wait_until(function()
        pok, admin_client = pcall(helpers.admin_client)
        if not pok then
          return false
        end
        local res = assert(admin_client:send {
          method = "GET",
          path = "/upstreams/my-upstream/health",
        })
        -- A 404 status may indicate that my-upstream is being recreated, so we
        -- should wait until timeout before failing this test
        if res.status == 404 then
          return false
        end

        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        admin_client:close()

        return "127.0.0.1:15556" == json.data[1].target and
               "HEALTHCHECKS_OFF" == json.data[1].health
      end, 10)
    end)
  end

  describe("errors", function()
    it("complains about missing PID if not already running", function()
      helpers.prepare_prefix()
      assert(helpers.kong_exec("prepare --prefix " .. helpers.test_conf.prefix))

      local ok, err = helpers.kong_exec("reload --prefix " .. helpers.test_conf.prefix)
      assert.False(ok)
      assert.matches("Error: nginx not running in prefix: " .. helpers.test_conf.prefix, err, nil, true)
    end)

    if strategy ~= "off" then
      it("complains when database connection is invalid", function()
        assert(helpers.start_kong({
          proxy_listen = "0.0.0.0:9002"
        }, nil, true))

        local ok = helpers.kong_exec("reload --conf " .. helpers.test_conf_path, {
          database = strategy,
          pg_port = 1234,
          cassandra_port = 1234,
        })

        assert.False(ok)
      end)
    end
  end)
end)

end


describe("#only key-auth plugin invalidation on dbless reload #off", function()
  it("(regression - issue 5705)", function()
    local admin_client
    local proxy_client
    local yaml_file = helpers.make_yaml_file([[
      _format_version: "1.1"
      services:
      - name: my-service
        url: https://127.0.0.1:15556
        plugins:
        - name: key-auth
        routes:
        - name: my-route
          paths:
          - /
      consumers:
      - username: my-user
        keyauth_credentials:
        - key: my-key
    ]])

    finally(function()
      --os.remove(yaml_file)
      if admin_client then
        admin_client:close()
      end
      if proxy_client then
        proxy_client:close()
      end
      helpers.stop_kong(nil, true)
    end)

    assert(helpers.start_kong({
      database = "off",
      declarative_config = yaml_file,
      nginx_worker_processes = 1,
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }))

    proxy_client = helpers.proxy_client()
    local res = assert(proxy_client:send {
      method  = "GET",
      path    = "/",
      headers = {
        ["apikey"] = "my-key"
      }
    })
    assert.res_status(200, res)

    res = assert(proxy_client:send {
      method  = "GET",
      path    = "/",
      headers = {
        ["apikey"] = "my-new-key"
      }
    })
    assert.res_status(401, res)

    proxy_client:close()

    admin_client = assert(helpers.admin_client())
    local res = assert(admin_client:send {
      method = "GET",
      path = "/key-auths",
    })
    assert.res_status(200, res)

    local body = assert.res_status(200, res)
    local json = cjson.decode(body)
    assert.same(1, #json.data)
    assert.same("my-key", json.data[1].key)
    admin_client:close()

    helpers.make_yaml_file([[
      _format_version: "1.1"
      services:
      - name: my-service
        url: https://127.0.0.1:15556
        plugins:
        - name: key-auth
        routes:
        - name: my-route
          paths:
          - /
      consumers:
      - username: my-user
        keyauth_credentials:
        - key: my-new-key
    ]], yaml_file)
    assert(helpers.reload_kong("off", "reload --prefix " .. helpers.test_conf.prefix, {
      declarative_config = yaml_file,
      database = "off",
      nginx_worker_processes = 1,
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }))

    local res

    helpers.wait_until(function()
      admin_client = assert(helpers.admin_client())

      res = assert(admin_client:send {
        method = "GET",
        path = "/key-auths",
      })
      assert.res_status(200, res)
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      admin_client:close()

      if #json.data ~= 1 then
        return nil, { message = "expected 1 key-auth credential", data = json }
      end

      if json.data[1].key ~= "my-new-key" then
        return nil, { message = "unexpected credential key value", data = json }
      end

      return true
    end, 5)

    helpers.wait_until(function()
      proxy_client = helpers.proxy_client()
      res = assert(proxy_client:send {
        method  = "GET",
        path    = "/",
        headers = {
          ["apikey"] = "my-key"
        }
      })
      proxy_client:close()
      return res.status == 401
    end, 5)

    helpers.wait_until(function()
      proxy_client = helpers.proxy_client()
      res = assert(proxy_client:send {
        method  = "GET",
        path    = "/",
        headers = {
          ["apikey"] = "my-new-key"
        }
      })
      local body = res:read_body()
      proxy_client:close()
      return body ~= [[{"message":"Invalid authentication credentials"}]]
    end, 5)

    admin_client = assert(helpers.admin_client())
    local res = assert(admin_client:send {
      method = "GET",
      path = "/key-auths",
    })
    assert.res_status(200, res)

    local body = assert.res_status(200, res)
    local json = cjson.decode(body)
    assert.same(1, #json.data)
    assert.same("my-new-key", json.data[1].key)
    admin_client:close()

  end)
end)
