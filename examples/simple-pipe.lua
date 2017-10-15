-- This example simply lists the contents of `/` and intercept its
-- output with a pipe.

local cqueues = require 'cqueues'
local subprocess = require 'xcq.subprocess'

assert(cqueues.new():wrap(function()
  local p = subprocess.spawn{ 'ls', '-l',
    cwd = '/',
    stdout = subprocess.PIPE,
  }

  -- read lines and prefix them with "ls>"
  for l in p.stdout:lines() do
    print("ls> ", l)
  end

  -- check that the whole thing worked
  assert(p:wait() == 0, "process exited with a non-zero status")
end):loop())
