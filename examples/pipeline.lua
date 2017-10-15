-- This example shows hoe to build a pipeline using multiple processes. Here
-- the first process will simply uppercase the data that we feed into it, and
-- the second will format it with `cowsay`.
--
-- It also shows that the data can be fed by another coroutine, with a small
-- delay, while the main coroutine wait for the result.

local cqueues = require 'cqueues'
local subprocess = require 'xcq.subprocess'

assert(cqueues.new():wrap(function()
  local text = #arg > 0 and table.concat(arg, ' ') or 'hello, world!'

  -- extremely convoluted :upper()
  local tr = subprocess.spawn { 'tr', '[a-z]', '[A-Z]',
    stdin  = subprocess.PIPE,
    stdout = subprocess.PIPE,
  }

  -- do something fun with that
  local cowsay = subprocess.spawn { 'cowsay',
    stdin = tr.stdout,
    stdout = subprocess.PIPE,
  }

  -- wait a bit before actually writing text
  cqueues.running():wrap(function()
    cqueues.sleep(0.5)
    tr.stdin:write(text, '\n')
    tr.stdin:close()
  end)

  -- wait for the result
  local result = cowsay.stdout:read('*a')
  io.stdout:write(string.rep('-', 80), '\n')
  print(result)
  io.stdout:write(string.rep('-', 80), '\n')
end):loop())
