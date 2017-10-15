-- This example shows how to use signals on other processes and check for
-- incorrect termination of spawned processes.

local cqueues = require 'cqueues'
local signal = require 'cqueues.signal'
local subprocess = require 'xcq.subprocess'

assert(cqueues.new():wrap(function()
  -- Spawn a process that takes 10 seconds to complete
  local p = subprocess.spawn { 'sleep', '10' }

  -- but kill it after 2 seconds
  cqueues.running():wrap(function()
    print('sleeping for 2 seconds')
    cqueues.sleep(2)
    print("alright, that's too long now")
    p:kill(signal.SIGKILL)
  end)

  code, status = p:wait()
  assert(status == 'killed' and code == 9)
  print('bye')
end):loop())
