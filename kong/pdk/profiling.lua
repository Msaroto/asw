local update_time = ngx.update_time
local now = ngx.now
local sub = string.sub
local ceil = math.ceil
local select = select
local concat = table.concat
local running = coroutine.running
local tostring = tostring
local worker_id = ngx.worker.id


local function new(self)
  local info = self.log.info
  return {
    start = function(...)
      update_time()
      local wid = worker_id()
      local start = now() * 1000
      info("BEGIN ", start, " WORKER ", wid, " THREAD ", sub(tostring(running()), 11), " ", ...)
      local msg = concat({ ... })
      return function(...)
        update_time()
        local cid = sub(tostring(running()), 11)
        local stop = now() * 1000
        local duration = ceil(stop - start)
        local argc = select("#", ...)
        if argc == 0 then
          info("ENDED ", stop, " WORKER ", wid, " THREAD ", cid, " ", msg, " TOOK ", duration, " ms")
        else
          local msg = concat({ ... })
          info("ENDED ", stop, " WORKER ", wid, " THREAD ", cid, " ", msg, " TOOK ", duration, " ms (", msg, ")")
        end
      end
    end
  }
end


return {
  new = new,
}
