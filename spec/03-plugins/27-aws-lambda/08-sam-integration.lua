local helpers = require "spec.helpers"
local sam = require "spec.fixtures.aws-sam"

for _, strategy in helpers.each_strategy() do
  describe("Plugin: AWS Lambda with SAM local lambda service [#" .. strategy .. "]", function()
    local proxy_client
    local admin_client
    local sam_port

    lazy_setup(function ()
      sam.setup()
      local ret
      ret, sam_port = sam.start_local_lambda()
      if not ret then
        assert(false, sam_port)
      end

      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      }, { "aws-lambda" })

      local route1 = bp.routes:insert {
        hosts = { "lambda.com" },
      }

      bp.plugins:insert {
        name     = "aws-lambda",
        route    = { id = route1.id },
        config   = {
          host          = "localhost",
          port          = sam_port,
          aws_key       = "mock-key",
          aws_secret    = "mock-secret",
          aws_region    = "us-east-1",
          function_name = "HelloWorldFunction",
        },
      }
    end)

    lazy_teardown(function()
      sam.stop_local_lambda()
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
      admin_client = helpers.admin_client()
    end)

    after_each(function ()
      proxy_client:close()
      admin_client:close()
    end)

    describe("with local HTTP endpoint", function ()
      lazy_setup(function()
        assert(helpers.start_kong({
          database   = strategy,
          plugins = "aws-lambda",
          nginx_conf = "spec/fixtures/custom_nginx.template",
        }, nil, nil, nil))
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      it("invoke a simple function", function ()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/",
          headers = {
            host = "lambda.com"
          }
        })
        assert.truthy(res)
        assert.truthy(true)
      end)
    end)
  end)
end
