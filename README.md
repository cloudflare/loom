LOOM
====

It's a replacement / enhancement of the `-jdump` option included in LuaJIT.

As a command line argument
===

Just put it in a `jit/` directory within `package.path` or `$LUA_PATH`, typically `'/usr/local/share/luajit-2.1..../jit/'`; but it also works in `'/usr/local/share/lua/5.1/jit/'` or even `'./jit/'`.  Then it can be used as an argument to LuaJIT in the form:

**`-jloom[=<tmpl>[,<out>]]`**

`<tmpl>` is a template file (default `'loom.html'`) and `<out>` is an output file name (default `io.stdout`).

Lua API
===

If you want to report traces on just part of your code, it's better to use it explicitly.

**`local loom = require 'jit.loom'`**

As any module, you have to `require()` it first.

**`loom.on()`**

Starts recording all JIT events and traces.

**`traces, funcs = loom.off()`**

**`report = loom.off([f [, ...]])`**

Stops recording and performs any processing and cross references needed to actually generate a report.

Called without any arguments, returns two Lua arrays, one with the processed trace information and a second one with all the functions involved in those traces execution.

The second form is equivalent to

    do
        local traces, funcs = loom.off()
        report = f(traces, funcs, ...)
    end

That is, both return values (the `traces` and `funcs` arrays) are passed to the given function `f`, together with any extra argument, and returns any return value(s) of `f`.

**`loom.start(tmpl, out)`**

Implements the `-jloom[=tmpl[,out]]` option. The `tmpl` argument is passed to `loom.template()` to create a reporting function.  If omitted, defaults to `'loom.html'`.  The `out` parameter is either a writeable open file or a file name where the report is written into (after formatting by the template), defaults to `io.stdout`.  When the Lua VM is terminated normally, `loom.off()` is called with the reporting function created by the given template.,

### Utility functions

There are some functions included in the `loom` package to help formatting a report.

**`f = loom.template(tmpl)`**

The string `tmpl` is a report template using the template syntax described below.  If it doesn't contain any line break, is interpreted as a pathname to read the template from a text file.

The template is compiled into a Lua function that takes some arguments (named with `{{@ name ...}}` tags) and outputs the result as a string.


**`loom.annotated(funcs, traces)`**

Returns an annotated listing of the source code of the given `funcs` and `traces` arrays.

**`loom.sortedpairs(t)`**

Returns an iterator that visits the same pairs as `pairs(t)`, but sorted by keys.


Template syntax
===

The included template implementation is based on Danila Poyarkov's [lua-template](https://github.com/dannote/lua-template), with a syntax more like Django's or Handlebar's, to make it more friendly to editors that help with HTML content.


### `{% lua code %}`

Embeds any Lua code

### `{{ expression }}`

Outputs the result of the Lua expression, with the `&'"</>` characters escaped.

### `{{= expression }}`

Outputs the result of the Lua expression verbatim, without any character escaping.

### `{{: 'fmt', args, ... }}`

Outputs the result of `string.format(fmt, args, ...)` without any escaping.

### `{{@ name ... }}`

Defines template argument names.  Each `name` must be a valid Lua variable name (that is, a sequence of letters, numbers or underscores not beginning with a number), separated by commas or spaces (or any non-alfanumeric-underscore character).
