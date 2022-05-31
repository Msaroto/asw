local update_time = ngx.update_time
local now = ngx.now
local ceil = math.ceil


local function new(self)
  local info = self.log.info
  return {
    start = function()
      update_time()
      local start = now() * 1000
      return function(...)
        update_time()
        local duration = ceil(now() * 1000 - start)
        info("took ", duration, " ms to ", ...)
      end
    end
  }
end


return {
  new = new,
}
