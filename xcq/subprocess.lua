local posix = require 'posix'
local unistd = require 'posix.unistd'
local syswait = require "posix.sys.wait"
local fcntl = require 'posix.fcntl'

local cqueues = require 'cqueues'
local signal = require 'cqueues.signal'
local socket = require 'cqueues.socket'
local promise = require 'cqueues.promise'
local errno = require 'cqueues.errno'

local pending = setmetatable({}, { __mode = 'v' })

local clearbit
if bit then       -- LuaJIT
  clearbit = function(a,b) return bit.band(a, bit.bnot(b)) end
elseif bit32 then -- Lua 5.2
  clearbit = function(a,b) return bit32.band(a, bit32.bnot(b)) end
else              -- hope for 5.3+
  clearbit = assert(
    load('return function(a,b) return a & ~b end'),
    'Lua version unsupported'
  )()
end

local PIPE = {}
local subprocess_mt = {}
subprocess_mt.__index = subprocess_mt

-- Signal handling loop, it is started after the first process is ran and
-- stopped when there is no more process to monitor, to be restarted again if
-- another process is ran. This is to avoid deadlocking the queue at the end
-- of the program.
local function handle_signals()
  local listener = signal.listen(signal.SIGCHLD)
  signal.block(signal.SIGCHLD)

  cqueues.running():wrap(function()
    while next(pending) ~= nil do
      -- TODO: handle cancellation in some way, otherwise we might have to wait
      -- for a child to die to find out th;at all managed processes have been
      -- garbage collected.
      listener:wait()
      -- maybe more than one child died
      repeat
        local pid, what, status = syswait.wait(-1, syswait.WNOHANG)
        -- not intersedted in the 'stopped' state
        if pending[pid] and (what == 'exited' or what == 'killed') then
          pending[pid]:set(true, status, what)
          pending[pid] = nil
        end
      -- nil is when the process don't have children anymore, 0 is when the
      -- process do have children, but no event to report and the NOHANG
      -- optiion causes the call to 'fail' with the status 0
      until pid == nil or pid == 0
    end

    -- no more children to wait for, unblock the signal and exit
    signal.unblock(signal.SIGCHLD)
  end)
end

local function check_file(f)
  if f == nil or         -- keep existing fd
     f == PIPE or        -- a pipe must be created
     type(f) == 'number' -- existing integer fd
  then
    return f
  end

  -- cqueues socket
  if socket.type(f) == 'socket' then return f:pollfd() end

  -- Lua file handle
  local ok, fd = pcall(posix.fileno, f)
  if ok and fd then return fd end

  error('file must be either nil, number, cqueues socket or Lua file handle')
end

local function spawn(desc)
  assert(type(desc) == 'table', 'expected a table')
  assert(#desc > 0, 'no command provided')

  -- copy the command
  local command = {}
  for i=1, #desc do
    command[i] = tostring(desc[i])
  end

  local self = setmetatable({
    command = command,
    executable = desc.executable or table.remove(command, 1),
    _stdin = check_file(desc.stdin),
    _stdout = check_file(desc.stdout),
    _stderr = check_file(desc.stderr),
    _status = promise.new(),
  }, subprocess_mt)

  if desc.autostart ~= false then
    local pid, msg, code = self:start()
    if not pid then return nil, msg, code end
  end

  return self
end

-- Perpare file descriptor for forking.
-- @param f The file descriptor (number or PIPE)
-- @param dir Direction for the parent (only for pipe)
-- @return child file descriptor number, or nil
-- @return parent socket handler, or nil
local function prepare_fd(f, dir)
  if type(f) == 'number' then
    return f, nil
  elseif f == PIPE then
    local r, w = posix.pipe()
    if dir == 'w' then
      return r, socket.fdopen(w)
    else
      return w, socket.fdopen(r)
    end
  end
  return nil, nil -- just forward I/O
end

local function prepare_fd_child(fd, dest)
  if not fd then return end
  assert(unistd.dup2(fd, dest))
  assert(unistd.close(fd))
  -- stdio needs to be blocking by default
  local flags = assert(fcntl.fcntl(dest, fcntl.F_GETFL))
  assert(fcntl.fcntl(dest, fcntl.F_SETFL, clearbit(flags, fcntl.O_NONBLOCK)))
end

--- Start the process.
-- The process id will be returned and stored in  the `pid` attribute.
-- If standard files are piped, they become available under the `stdin`,
-- `stdout` and `stderr` attributes.
function subprocess_mt:start()
  if self.pid then return nil, 'already started' end

  local install_handler = next(pending) == nil

  local stdinr, stdoutw, stderrw
  stdinr,  self.stdin  = prepare_fd(self._stdin,  'w')
  stdoutw, self.stdout = prepare_fd(self._stdout, 'r')
  stderrw, self.stderr = prepare_fd(self._stderr, 'r')

  -- the bootstrapping process after forking is as follows:
  -- PARENT: add child to the signal handling loop and close parent end of fds
  -- SYNC  : parent  send '1' to the sync socket
  -- CHILD : install child end of file descriptors
  -- CHILD : exec or write error to socket, the CLOEXEC will ensure parent
  --         will unblock on success
  -- PARENT: wait for the socket to be closed, or read error message
  -- in case of error in the child, the format is `errno\nerrmsg'
  local parent, child = socket.pair{ mode='bn', nonblock=false, cloexec=true }

  local pid, err = posix.fork()
  if not pid then return nil, err end
  if pid == 0 then
    -- child: wrap everything in a pcall'd function: any failure here could
    -- lead to undefined behavior as the child might continue to run as parent
    local ok, msg, code = xpcall(function()
      -- WARNING: starting from here, the current corroutine must not yield
      parent:close()
      -- use raw read to not return to the cqueues controller
      local ok, msg, code = unistd.read(child:pollfd(), 1)
      assert(ok == '1', msg or 'wrong sync from parent')

      -- setup I/O
      if self.stdin then self.stdin:close() end
      if self.stdout then self.stdout:close() end
      if self.stderr then self.stderr:close() end

      prepare_fd_child(stdinr,  0)
      prepare_fd_child(stdoutw, 1)
      prepare_fd_child(stderrw, 2)

      local ok, msg, code = posix.execp(self.executable, self.command)
      return msg, code
    end, debug.traceback)

    -- we are not supposed to return, at thos point an error occured
    unistd.write(child:pollfd(), ok and
      string.format('%d\n%s', code, msg) or -- subprocess failed
      string.format('-1\n%s', msg))         -- initialization failed
    -- the process MUST be aborted, otherwise the child will continue as parent
    os.exit(2)
  else
    -- parent
    child:close()

    self.pid = pid
    pending[pid] = self._status

    if install_handler then
      handle_signals()
    end

    if stdinr  then posix.close(stdinr)  end
    if stdoutw then posix.close(stdoutw) end
    if stderrw then posix.close(stderrw) end

    -- all clear the child is free to go
    parent:write('1')
    local status, err = parent:read('*a')
    if status then
      -- the child wrote something on the sync socket: an error occured
      local errno, msg = status:match('(%-?%d+)\n(.*)')
      return nil, msg, tonumber(errno)
    elseif err then
      -- the socket itself had an error
      return nil, 'sync with child failed: ' .. errno.strerror(err), err
    end
  end
  return pid
end

--- Wait for the process to finish.
-- @return[1] Exit code of the process
-- @return[1] Exist status (`exited` or `killed`)
-- @return[2] If timeout is reached
function subprocess_mt:wait(timeout)
  return self._status:get(timeout)
end

--- Send a signal do the process.
-- @param signal numerical code of the signal to send
-- @see Mappings can be found in `posix.signal` or `cqueues.signal`
function subprocess_mt:kill(signal)
  if not self.pid then return nil, 'not started' end
  posix.kill(self.pid, signal)
end

return {
  spawn = spawn,
  PIPE = PIPE,
}
