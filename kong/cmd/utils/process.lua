local read_file = require("pl.file").read
local kill = require("resty.signal").kill

local tonumber = tonumber
local type = type

local E_EMPTY_PID_FILE = "PID file is empty"
local E_INVALID_PID_FILE = "PID file does not contain a valid PID"
local E_NO_SUCH_PID_FILE = "PID file does not exist"
local E_INVALID_PID_TYPE = "invalid PID type"
local E_PID_OUT_OF_RANGE = "PID must be >= 2"


---
-- Read and return the process ID from a pid file.
--
---@param  fname       string
---@return integer|nil pid
---@return nil|string  error
local function pid_from_file(fname)
  local data, err = read_file(fname)
  if not data then
    -- map penlight error to our own
    if err:lower():find("no such file", nil, true) then
      err = E_NO_SUCH_PID_FILE
    end

    return nil, err
  end

  -- strip whitespace
  data = data:gsub("^%s*(.-)%s*$", "%1")

  if #data == 0 then
    return nil, E_EMPTY_PID_FILE
  end

  local pid = tonumber(data)
  if not pid then
    return nil, E_INVALID_PID_FILE
  end

  return pid
end


---
-- Detects a PID from input and returns it as a number.
--
---@param  target      string|number
---@return integer|nil pid
---@return nil|string  error
local function get_pid(target)
  local typ = type(target)

  local pid, err

  if typ == "number" then
    pid = target

  elseif typ == "string" then
    -- for the sake of compatibility we're going to accept PID input as a
    -- numeric string, but this is potentially ambiguous with a PID file,
    -- so we'll try to load from a file first before attempting to treat
    -- the input as a numeric string
    pid, err = pid_from_file(target)

    -- PID was supplied as a numeric string (i.e. "123")
    if err == E_NO_SUCH_PID_FILE and tonumber(target) then
      pid = tonumber(target)
    end

  else
    return nil, E_INVALID_PID_TYPE
  end

  if not pid then
    return nil, err

  elseif pid < 1 then
    return nil, E_PID_OUT_OF_RANGE
  end

  return pid
end


---
-- Target processes may be referenced by their integer id (PID)
-- or by a pid filename.
--
---@alias kong.cmd.utils.process.target
---| integer # pid
---| string  # pid file


---
-- Send a signal to a process.
--
-- The signal may be specified as a name ("TERM") or integer (15).
--
---@param  target      kong.cmd.utils.process.target
---@param  sig         resty.signal.name|integer
---@return boolean|nil ok
---@return nil|string  error
local function signal(target, sig)
  local pid, err = get_pid(target)

  if not pid then
    return nil, err
  end

  return kill(pid, sig)
end


---
-- Check for the existence of a process.
--
-- Under the hood this sends the special `0` signal to check the process state.
--
-- Returns:
--   * true|false under normal circumstances
--   * nil+error for invalid input
--
-- Throws for unexpected errors from resty.signal.
--
-- Callers should decide for themselves how strict they must be when handling
-- errors. For instance, when NGINX is starting up there is a period where the
-- pidfile may be empty or non-existent, which will result in this function
-- returning nil+error. For some callers this might be expected and acceptible,
-- but for others it may not.
--
---@param  target      kong.cmd.utils.process.target
---@return boolean|nil exists
---@return nil|string  error
local function exists(target)
  local pid, err = get_pid(target)
  if not pid then
    return nil, err
  end

  local ok
  ok, err = kill(pid, 0)

  if ok then
    return true

  elseif err == "No such process" then
    return false
  end

  error(err or "unexpected error from resty.signal.kill()")
end


return {
  exists = exists,
  pid_from_file = pid_from_file,
  signal = signal,
  pid = get_pid,

  E_EMPTY_PID_FILE = E_EMPTY_PID_FILE,
  E_NO_SUCH_PID_FILE = E_NO_SUCH_PID_FILE,
  E_INVALID_PID_FILE = E_INVALID_PID_FILE,
  E_INVALID_PID_TYPE = E_INVALID_PID_TYPE,
  E_PID_OUT_OF_RANGE = E_PID_OUT_OF_RANGE,
}
