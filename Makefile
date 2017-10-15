
# for tests involving changing user ids, the tests is run as fakeroot and tries
# to drop privileges to the current user
USERNAME=$(shell id -un)
USERID=$(shell id -u)
GROUP=$(shell id -g)

.PHONY: lint
lint:
	luacheck xcq/*.lua

# check that the examples actually work
.PHONY: examples
examples: examples/*.lua
	$(foreach f, $^, lua $(f);)

.PHONY: test
test: lint examples
	tsc ./tests/subprocess.lua
	TEST_USERNAME=$(USERNAME) TEST_USERID=$(TEST_USERID) TEST_GROUP=$(GROUP) fakeroot tsc ./tests/privileged.lua

.PHONY: doc
doc:
	ldoc .
