-- This example demonstrate how to run multiple processes concurrently. It uses
-- the fact that processes are pollable objects to wait for their termination.

local cqueues = require 'cqueues'
local subprocess = require 'xcq.subprocess'
local unpack = unpack or table.unpack

assert(cqueues.new():wrap(function()
  local processes = {}
  for i=1, 4 do
    local p = subprocess.spawn { 'sleep', tostring(i) }
    processes[i] = p
  end

  -- wait for all processes to finish
  while next(processes) do
    local ready = cqueues.poll(unpack(processes))
    -- retrieve how long this process slept
    local second = tonumber(ready.command[2])

    -- get exit status (the 0 timeout ensures that we don't actually wait to
    -- get this data)
    print(string.format('process %d exited: ', second), ready:wait(0))

    -- remove the finished process from the table (normally it should be the
    -- first one)
    assert(table.remove(processes, 1) == ready)
  end
end):loop())
