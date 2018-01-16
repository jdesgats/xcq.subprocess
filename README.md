# cqueues subprocess management

`xcq.subprocess` is a library to manage subprocesses from a [cqueues][cq]
controller.

Like all other I/O operations in cqueues, reading from, writing to or waiting
for a subprocess is asynchronous.

* Can spawn multiple processes and use async I/O to communicate with them
* Lua file handles, cqueues socket, or pipes can be used for stdin/stdout/stderr
* Signals

This library aims to be a simple, *just works* solution to run and interact
with subprocesses. Advanced use cases are not (yet) supported. The priority
is to keep a simple to use and clear interface while make it very hard to shoot
yourself in the foot.

Status
------

Alpha: might contain bugs, API not frozen, some features are unfinished:

* Environment is not cleared for now
* Spawning a process as another user still has rough edges, and probably
  security issues (e.g. no supplementary group management)
* Opened files are not cleared. This shouldn't be a problem with `cqueues`
  file descriptors as they are `CLOEXEC` by default, but this is not the
  case for raw Lua ones.
* `luaposix` is big, investigate on `lunix` for a possible replacement
* Use `posix_spawn` instead of `fork`/`exec`?

Installation
------------

### Dependencies

* [cqueues][cq]
* [luaposix][luaposix] for low level system calls

### LuaRocks (no stable release yet)

```sh
luarocks install https://github.com/jdesgats/xcq.subprocess/raw/master/rockspecs/xcq-subprocess-scm-1.rockspec
```

### Manually

Either put the `xcq` project somewhere in your Lua path after installing the
above dependencies.

API
---

The API is loosely based on Python's [subprocess][py] library but differs
when it is possible to take advantage of Lua/cqueues specificities.

See the detailed documentation for details, and the `examples` directory for
more concrete use cases.

[cq]: http://25thandclement.com/~william/projects/cqueues.html
[py]: https://docs.python.org/3/library/subprocess.html
[luaposix]: https://github.com/luaposix/luaposix


