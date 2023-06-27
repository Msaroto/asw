local helpers = require "spec.helpers"

describe("Admin API - CORS -", function()
  for _, admin_gui_url in ipairs({ "", "http://admin.api:9100", "http://admin.api:9100/path/to/any/way" }) do
    describe('when |admin_gui_url| is "' .. admin_gui_url .. '",', function ()

      local client

      lazy_setup(function()
        assert(helpers.start_kong({
          database = "off",
          admin_gui_listen = "127.0.0.1:9002",
          admin_gui_url = admin_gui_url,
        }))

        client = helpers.admin_client()
      end)

      teardown(function()
        if client then
          client:close()
        end
        helpers.stop_kong()
      end)

      describe("Pre-flight request", function ()
        it("should return fixed allow methods", function ()
          local res, err = client:send({
            path = "/",
            method = "OPTIONS",
            headers = {}
          })
          assert.is_nil(err)
          assert.res_status(204, res)
          assert.equal("GET,PUT,PATCH,POST,DELETE", res.headers["Access-Control-Allow-Methods"])

          local res, err = client:send({
            path = "/",
            method = "OPTIONS",
            headers = {
              ["Access-Control-Request-Method"] = "PATCH",
            }
          })
          assert.is_nil(err)
          assert.res_status(204, res)
          assert.equal("GET,PUT,PATCH,POST,DELETE", res.headers["Access-Control-Allow-Methods"])
        end)

        it("should allow headers from the request", function ()
          local res, err = client:send({
            path = "/",
            method = "OPTIONS",
            headers = {}
          })
          assert.is_nil(err)
          assert.res_status(204, res)
          assert.is_nil(res.headers["Access-Control-Allow-Headers"])

          local res, err = client:send({
            path = "/",
            method = "OPTIONS",
            headers = {
              ["Access-Control-Request-Headers"] = "X-Header-1,X-Header-2",
            }
          })
          assert.is_nil(err)
          assert.res_status(204, res)
          assert.equal("X-Header-1,X-Header-2", res.headers["Access-Control-Allow-Headers"])
        end)

        it("should return the correct |AC-Allow-Origin| header when \"Origin\" is present in request headers", function ()
          local res, err = client:send({
            path = "/",
            method = "OPTIONS",
            headers = {
              ["Origin"] = "http://example.com",
            }
          })
          local expected_allow_origin = admin_gui_url ~= "" and "http://admin.api:9100" or "http://example.com"

          assert.is_nil(err)
          assert.res_status(204, res)
          assert.equal(expected_allow_origin, res.headers["Access-Control-Allow-Origin"])
        end)

        it("should return the correct |AC-Allow-Origin| header when \"Origin\" is absent in request headers", function ()
          local res, err = client:send({
            path = "/",
            method = "OPTIONS",
            headers = {}
          })
          local expected_allow_origin = admin_gui_url ~= "" and "http://admin.api:9100" or "*"

          assert.is_nil(err)
          assert.res_status(204, res)
          assert.equal(expected_allow_origin, res.headers["Access-Control-Allow-Origin"])
        end)
      end)

      describe("Main request", function ()
        it("should not respond to |AC-Request-Method| or |AC-Request-Headers| headers", function ()
          local res, err = client:send({
            path = "/",
            method = "GET",
            headers = {
              ["Access-Control-Request-Method"] = "PATCH",
              ["Access-Control-Request-Headers"] = "X-Header-1,X-Header-2",
            }
          })
          assert.is_nil(err)
          assert.res_status(200, res)
          assert.equal(nil, res.headers["Access-Control-Allow-Methods"])
          assert.equal(nil, res.headers["Access-Control-Allow-Headers"])
        end)

        it("should return the correct |AC-Allow-Origin| header when \"Origin\" is present in request headers", function ()
          local res, err = client:send({
            path = "/",
            method = "GET",
            headers = {
              ["Origin"] = "http://example.com",
            }
          })
          local expected_allow_origin = admin_gui_url ~= "" and "http://admin.api:9100" or "http://example.com"

          assert.is_nil(err)
          assert.res_status(200, res)
          assert.equal(expected_allow_origin, res.headers["Access-Control-Allow-Origin"])
        end)

        it("should return the correct |AC-Allow-Origin| header when \"Origin\" is absent in request headers", function ()
          local res, err = client:send({
            path = "/",
            method = "GET",
            headers = {}
          })
          local expected_allow_origin = admin_gui_url ~= "" and "http://admin.api:9100" or "*"

          assert.is_nil(err)
          assert.res_status(200, res)
          assert.equal(expected_allow_origin, res.headers["Access-Control-Allow-Origin"])
        end)
      end)
    end)
  end
end)
