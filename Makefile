
# for tests involving changing user ids, the tests is run as fakeroot and tries
# to drop privileges to the current user
USERNAME=$(shell id -un)
USERID=$(shell id -u)
GROUP=$(shell id -g)

test:
	tsc ./tests/subprocess.lua
	TEST_USERNAME=$(USERNAME) TEST_USERID=$(TEST_USERID) TEST_GROUP=$(GROUP) fakeroot tsc ./tests/privileged.lua
