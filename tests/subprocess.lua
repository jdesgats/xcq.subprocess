
local cqueues = require 'cqueues'
local cq = require 'telescope.cqueues'
local signal = require 'cqueues.signal'
local socket = require 'cqueues.socket'
local errno = require 'cqueues.errno'
local posix = require 'posix'
local unistd = require 'posix.unistd'
local fcntl = require 'posix.fcntl'
local stdlib = require 'posix.stdlib'
local subprocess= require 'xcq.subprocess'

describe('subprocess runner', function()
  before(function()
    -- prevent deadlocks in case of failure: the longest test so far is
    -- supposed to last 5 seconds
    socket.settimeout(10)
  end)

  cq.test('non-autostart run', function()
    local p = subprocess.spawn{ 'true', autostart = false }
    assert_nil(p.pid)
    local pid = p:start()
    assert_type(pid, 'number')
    assert_equal(p.pid, pid)

    local code, status = p:wait()
    assert_equal(0, code)
    assert_equal('exited', status)
  end)

  cq.test('basic run', function()
    local p = subprocess.spawn{ 'true' }
    assert_type(p.pid, 'number')
    local code, status = p:wait()
    assert_equal(0, code)
    assert_equal('exited', status)

    -- same with a non-zero exit
    local code, status = subprocess.spawn{ 'false' }:wait()
    assert_equal(1, code)
    assert_equal('exited', status)
  end)

  cq.test('signal handling', function()
    local p = subprocess.spawn{ 'sleep', 60 }
    p:kill(signal.SIGTERM)
    local code, status = p:wait()
    assert_equal('killed', status)
    assert_equal(signal.SIGTERM, code)
  end)

  cq.test('arguments', function()
    local code, status = subprocess.spawn{ 'sh', '-c', 'exit 4' }:wait()
    assert_equal(4, code)
    assert_equal('exited', status)
  end)

  cq.test('a process is a pollable object', function()
    local p = subprocess.spawn{ 'sleep', '0.5' }
    assert_equal(p, cqueues.poll(p, 1), ':poll() returns the process instance')
    -- check that the process is actually finished (no :wait() call)
    assert_equal(0, p._code)
    assert_equal('exited', p._what)
    -- wait anyway, it should return instantly
    assert_equal(0, p:wait(0))
  end)

  cq.test('stdin/stdout pipe', function()
    local p = subprocess.spawn{ 'cat', stdin=subprocess.PIPE, stdout=subprocess.PIPE }
    p.stdin:write('hello, world\n')
    assert_equal(p.stdout:read('*l'), 'hello, world')

    p.stdin:write('data from pipe\n')
    p.stdin:close()
    assert_equal(p.stdout:read('*a'), 'data from pipe\n')

    local code, status = p:wait()
    assert_equal(0, code)
    assert_equal('exited', status)
  end)

  cq.test('stdout and stderr data', function(q)
    local p = subprocess.spawn{
      'sh', '-c', 'echo "some output"; echo "an error" >&2; echo "more output"',
      stdout=subprocess.PIPE,
      stderr=subprocess.PIPE,
    }
    q:wrap(function()
      assert_equal(p.stdout:read('*l'), 'some output')
      assert_equal(p.stdout:read('*l'), 'more output')
      assert_nil(p.stdout:read('*l'))
    end)
    q:wrap(function()
      assert_equal(p.stderr:read('*l'), 'an error')
      assert_nil(p.stderr:read('*l'))
    end)

    local code, status = p:wait()
    assert_equal(0, code)
    assert_equal('exited', status)
  end)

  cq.test('multiple subprocesses', function(q)
    local start = cqueues.monotime()
    local ps = {}
    for i=1,5 do
      local p = subprocess.spawn{
        'sh', '-c', string.format('sleep %d; echo "proc %d"; exit %d', i,i,i),
        stdout = subprocess.PIPE,
      }

      q:wrap(function()
        local out = p.stdout:read('*a')
        assert_equal(out, string.format('proc %d\n', i))
        local dur = cqueues.monotime() - start
        assert(dur > i - 0.5 and dur < i + 0.5,
               string.format('got output of proc %d after %f sec', i, dur))
      end)

      ps[i] = p
    end

    for i=1,5 do
      local code, status = ps[i]:wait()
      assert_equal(i, code)
      assert_equal('exited', status)
      local dur = cqueues.monotime() - start
      assert(dur > i - 0.5 and dur < i + 0.5,
             string.format('got exit code of proc %d after %f sec', i, dur))
    end
  end)

  cq.test('pipe from cqueues socket', function()
    local parent, child = socket.pair()
    local p = subprocess.spawn{ 'cat', stdin=child, stdout=subprocess.PIPE }

    parent:write('hello from parent!\n')
    parent:close()
    assert_equal(p.stdout:read('*a'), 'hello from parent!\n')

    local code, status = p:wait()
    assert_equal(0, code)
    assert_equal('exited', status)
  end)

  cq.test('pipe from a Lua file', function()
    local tmp = os.tmpname()
    local tmpr, tmpw = io.open(tmp, 'r'), io.open(tmp, 'w')
    os.remove(tmp)
    tmpw:write('hello tmpfile\n')
    tmpw:close()

    local p = subprocess.spawn{ 'cat', stdin=tmpr, stdout=subprocess.PIPE }
    -- XXX: maybe subprocess module should do it itself (optionally)
    tmpr:close()
    assert_equal(p.stdout:read('*a'), 'hello tmpfile\n')

    local code, status = p:wait()
    assert_equal(0, code)
    assert_equal('exited', status)
  end)

  cq.test('pipe from a bare file descriptor', function()
    local r, w = unistd.pipe()
    fcntl.fcntl(w, fcntl.F_SETFD, fcntl.FD_CLOEXEC)

    local p = subprocess.spawn{ 'cat', stdin=r, stdout=subprocess.PIPE }
    unistd.close(r)
    assert(unistd.write(w, 'hello from pipe\n'))
    unistd.close(w)
    assert_equal(p.stdout:read('*a'), 'hello from pipe\n')

    local code, status = p:wait()
    assert_equal(0, code)
    assert_equal('exited', status)
  end)

  cq.test('pipe to a cqueues socket', function()
    local parent, child = socket.pair()
    local p = subprocess.spawn{ 'echo', 'hello cqueues', stdout=child }

    -- XXX: maybe subprocess module should do it itself (optionally)
    child:close()

    assert_equal(parent:read('*a'), 'hello cqueues\n')
    local code, status = p:wait()
    assert_equal(0, code)
    assert_equal('exited', status)
  end)

  cq.test('pipe to a Lua file', function()
    local tmp = os.tmpname()
    local tmpr, tmpw = io.open(tmp, 'r'), io.open(tmp, 'w')
    os.remove(tmp)

    local p = subprocess.spawn{ 'echo', 'hello Lua file', stdout=tmpw }
    -- XXX: maybe subprocess module should do it itself (optionally)
    tmpw:close()

    local code, status = p:wait()
    assert_equal(0, code)
    assert_equal('exited', status)
    assert_equal(tmpr:read('*a'), 'hello Lua file\n')
  end)

  cq.test('pipe to a bare file descriptor', function()
    local r, w = unistd.pipe()

    local p = subprocess.spawn{ 'echo', 'hello file descriptor', stdout=w }
    unistd.close(w)
    assert_equal(unistd.read(r, 1024), 'hello file descriptor\n')

    local code, status = p:wait()
    assert_equal(0, code)
    assert_equal('exited', status)
  end)

  cq.test('pipeline', function()
    local p1 = subprocess.spawn{ 'echo', 'hello, pipeline', stdout=subprocess.PIPE }
    local p2 = subprocess.spawn{ 'tr', '[:lower:]', '[:upper:]', stdin=p1.stdout, stdout=subprocess.PIPE }

    assert_equal(p2.stdout:read('*a'), 'HELLO, PIPELINE\n')
    local code, status = p1:wait()
    assert_equal(0, code)
    assert_equal('exited', status)
    local code, status = p2:wait()
    assert_equal(0, code)
    assert_equal('exited', status)
  end)

  cq.test('non-existent executable', function()
    local ok, err, code = subprocess.spawn{ '/foo/bar' }
    assert_nil(ok)
    assert_type(err, 'string')
    assert_equal(code, errno.ENOENT)
  end)

  cq.test('missing rights', function()
    local tmp = os.tmpname()
    local tmpw = assert(io.open(tmp, 'w'))
    assert(tmpw:write('#!/bin/sh\necho this text should not appear\n'))
    assert(tmpw:close())

    local ok, err, code = subprocess.spawn{ tmp }
    os.remove(tmp)
    assert_nil(ok)
    assert_type(err, 'string')
    assert_equal(code, errno.EACCES)
  end)

  cq.test('do not change dir by default', function()
    local parentdir = unistd.getcwd()
    local p = subprocess.spawn{ 'pwd', stdout=subprocess.PIPE }
    assert_equal(parentdir .. '\n', p.stdout:read('*a'))
    assert_equal(0, (p:wait()))
  end)

  cq.test('change directory (dir exists)', function()
    local parentdir = unistd.getcwd()
    local tmp = stdlib.mkdtemp('/tmp/test-xcq-XXXXXX') -- TODO: use $TMPDIR if available

    local p = subprocess.spawn{ 'pwd', stdout=subprocess.PIPE, cwd=tmp }
    assert_equal(tmp .. '\n', p.stdout:read('*a'))
    assert_equal(0, (p:wait()))

    -- check that the parent is still at the same place
    assert_equal(parentdir, unistd.getcwd())
  end)

  cq.test('change directory (dir not exists)', function()
    local parentdir = unistd.getcwd()
    local ok, msg, code = subprocess.spawn{ 'pwd', stdout=subprocess.PIPE, cwd='/foo/bar' }
    assert_nil(ok)
    assert_equal(errno.ENOENT, code)
  end)

  local function process_env(out)
    local t, n = {}, 0
    for l in out:lines() do
      local k,v = l:match('^(.-)=(.*)$')
      if not k then error(string.format('failed to parse: %q', l)) end
      t[k] = v
      n = n + 1
    end
    return t, n
  end

  cq.test('environment variables', function()
    local p = subprocess.spawn{ 'env', env={ FOO='bar' }, stdout=subprocess.PIPE }
    local env, nenv = process_env(p.stdout)
    assert_equal(0, (p:wait()))
    assert_equal('bar', env.FOO)
    assert_greater_than(nenv, 1) -- the existing environment is still there
    assert_equal(os.getenv('PATH'), env.PATH)
  end)

  -- at least check that the call fails correctly
  cq.test('drop privileges (not root)', function()
    local ok, msg = pcall(subprocess.spawn, { 'id', user='julien' })
    assert_equal(false, ok)
    assert_match('you need to be root to change user$', msg)
  end)

  cq.test('change executable name', function()
    local p = assert(subprocess.spawn { 'foobar', '-c', 'echo $0',
      executable='/bin/sh',
      stdout=subprocess.PIPE,
    })

    assert_equal('foobar\n', p.stdout:read('*a'))
    assert_equal(0, p:wait())
  end)
end)

