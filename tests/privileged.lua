-- these tests need to be run as (fake)root

local cq = require 'telescope.cqueues'
local subprocess= require 'xcq.subprocess'
local unistd = require 'posix.unistd'

-- check that the test is set up correctly
USERNAME=assert(os.getenv("TEST_USERNAME"), "please run the test with the Makefile")
USERID=assert(os.getenv("TEST_USERID"), "please run the test with the Makefile")
GROUP=assert(os.getenv("TEST_GROUP"), "please run the test with the Makefile")
assert(unistd.getuid() == 0, "please run the test with the Makefile")

describe('privileged subprocess runner', function()
  -- TODO: find a way to make portable tests for this one
  cq.test('drop privileges (user name)', function()
    local p = subprocess.spawn { 'id', '-u', user='julien', stdout=subprocess.PIPE }
    assert_equal('1000\n', p.stdout:read('*a'))
    assert_equal(0, (p:wait()))

    local p = subprocess.spawn { 'id', '-g', user='julien', stdout=subprocess.PIPE }
    assert_equal('100\n', p.stdout:read('*a'))
    assert_equal(0, (p:wait()))
  end)

  cq.test('drop privileges (user id)', function()
    local p = subprocess.spawn { 'id', '-u', user=1000, stdout=subprocess.PIPE }
    assert_equal('1000\n', p.stdout:read('*a'))
    assert_equal(0, (p:wait()))

    local p = subprocess.spawn { 'id', '-g', user=1000, stdout=subprocess.PIPE }
    assert_equal('100\n', p.stdout:read('*a'))
    assert_equal(0, (p:wait()))
  end)

  cq.test('drop privileges (unknown user)', function()
    -- in this case the program MUST crash, worst case scenario would be to
    -- continue to run the subprocess as root
    local ok, msg = pcall(subprocess.spawn, { 'id', user='qwertyuiop' })
    assert_equal(false, ok)
    assert_match('unknown user: qwertyuiop$', msg)
  end)
end)
