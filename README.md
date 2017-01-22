# cqueues subprocess management

`xcq.subprocess` is a library to manage subprocesses from a [cqueues][cq]
controller.

Features
--------

Like all other I/O operations in cqueues, reading from, writing to or waiting
for a subprocess is asynchronous.

* Can spawn multiple processes and use async I/O to communicate with them
* Lua file handles, cqueues socket, or pipes can be used for stdin/stdout/stderr
* Signals

Status
------

Alpha: might contain bugs, API not frozen

Dependencies
------------

* [cqueues][cq]
* [luaposix][luaposix] for low level system calls

API
---

The API is loosely based on Python's [`subprocess`][py] library but differs
when it is possible to take advantage of Lua/cqueues specificities.

**TODO**: API docs

[cq]: http://25thandclement.com/~william/projects/cqueues.html
[py]: https://docs.python.org/3/library/subprocess.html
[luaposix]: https://github.com/luaposix/luaposix


