# IniFile.jl

[![CI](https://github.com/JuliaIO/IniFile.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/JuliaIO/IniFile.jl/actions/workflows/CI.yml)
[![codecov](https://codecov.io/gh/JuliaIO/IniFile.jl/graph/badge.svg)](https://codecov.io/gh/JuliaIO/IniFile.jl)
[![Aqua QA](https://raw.githubusercontent.com/JuliaTesting/Aqua.jl/master/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)

Read, query, modify and write INI configuration files from Julia.

The format follows Python's
[`configparser`](https://docs.python.org/3/library/configparser.html), so files
written for Python programs read the same way. Sections and keys keep their
order, so a file read and written again keeps its layout.

## Installation

```julia
using Pkg
Pkg.add("IniFile")
```

## Example

Given `settings.ini`:

```ini
# Settings for the example
name = example

[server]
host = example.org
port = 8080
debug = off

[paths]
search =
    /usr/lib
    /opt/lib
```

```julia
using IniFile

ini = read(Inifile, "settings.ini")

get(ini, "server", "host")            # "example.org"
get(ini, "server", "timeout")         # nothing
get(ini, "server", "timeout", "30")   # "30"
get(ini, "server", "name")            # "example", from the defaults

get_int(ini, "server", "port")        # 8080
get_bool(ini, "server", "debug")      # false
get_float(ini, "server", "timeout", 30.0)  # 30.0

split(strip(get(ini, "paths", "search")), '\n')  # ["/usr/lib", "/opt/lib"]

set(ini, "server", "port", 9090)
set(ini, "logging", "level", "debug")   # creates the section
write("settings.ini", ini)
```

## Usage

### Reading

```julia
ini = read(Inifile, "file.ini")          # from a file
ini = read(Inifile, io)                  # from any IO stream
ini = read(Inifile, "file.ini"; lowercase_keys=true, inline_comment_prefixes=(";",))

ini = Inifile()                          # or create an empty one
read(ini, "file.ini")                    # and read into it (merges with its content)
```

Options of `Inifile(...)` and `read(Inifile, ...)`:

| Keyword | Default | Effect |
| --- | --- | --- |
| `lowercase_keys` | `false` | Store and look up keys in lowercase, so `Key` and `key` are the same key, as Python's `configparser` does by default. Section names stay case-sensitive. |
| `inline_comment_prefixes` | `()` | Prefixes such as `(";", "#")` that start a comment in the middle of a line, when they follow whitespace. Off by default, as in Python 3. |
| `strict` | `false` | Throw an `ArgumentError` for a malformed line instead of logging a warning and skipping it. |

### Querying

```julia
get(ini, "section", "key")                # value as a String, or nothing
get(ini, "section", "key", default)       # value, or default
get_bool(ini, "section", "key")           # Bool: 1/yes/true/on or 0/no/false/off, any case
get_int(ini, "section", "key")            # Int
get_float(ini, "section", "key")          # Float64
get_int(ini, "section", "key", default)   # default if the key is missing

has_section(ini, "section")
haskey(ini, "section", "key")
sections(ini)           # OrderedDict of section name => OrderedDict of key => value
section(ini, "section") # OrderedDict of key => value
defaults(ini)           # keys that appear before the first section header
get(ini, "key")         # a key in the defaults, or nothing
```

A lookup in a section falls back to the defaults when the section does not have
the key. The typed getters throw a `KeyError` for a missing key when no default
is given, and an `ArgumentError` naming the section, key and value when the value
cannot be parsed. In particular `get_bool` rejects values such as `Ture` instead
of reading them as `false`.

### Modifying and writing

```julia
set(ini, "section", "key", value)   # value is a string, number or Bool, stored as a string
set(ini, "section", "key", nothing) # remove the key
set(ini, "key", value)              # set a key in the defaults

write("file.ini", ini)              # or write(io, ini)
```

`write` keeps the order of sections and keys, writes `key = value`, puts a blank
line between sections, and writes multi-line values as indented continuation
lines. Comments in the original file are not kept.

## File format

```ini
; A comment
# Another comment

# Entries before the first section header are the defaults
default_key = value

[section name]
key = value
# The first `=` or `:` on a line separates the key and the value
other_key: value
empty =
# Lines indented further than the entry continue its value
long value = first line
    second line
```

- Blank lines and lines starting with `#` or `;` are ignored.
- Whitespace around keys and values is removed.
- Continuation lines are joined with `"\n"`.
- Inline comments, as in `key = value ; note`, are only removed when enabled
  with `inline_comment_prefixes`; otherwise they are part of the value.
- Malformed lines are skipped with a warning that gives the line number.

### Differences from Python's `configparser`

- Entries before the first section header are allowed and become the defaults.
  A `[DEFAULT]` section is an ordinary section.
- There is no value interpolation (`%(name)s` or `${name}`).
- Keys without a value (`allow_no_value`) are malformed.
- Repeated sections are merged and repeated keys overwrite earlier ones, as in
  `configparser` with `strict=False`.
- Python 2's `ConfigParser` always treated `;` after whitespace as a comment. To
  read such files the same way, use `inline_comment_prefixes=(";",)`.

## Upgrading from 0.5

Version 0.6 has breaking changes:

- Values are always `String`s. `set` stores `string(value)`, so
  `set(ini, "s", "k", 1.5)` followed by `get(ini, "s", "k")` returns `"1.5"`.
  Use `get_float`, `get_int` or `get_bool` to get typed values.
- `get(ini, section, key)` and `get(ini, key)` return `nothing` instead of
  `:notfound` for a missing key. Checks such as `value === :notfound` do not
  throw an error, they just stop matching, so search for `:notfound` and change
  them to `value === nothing`.
- `get(ini, key, default)` is removed, because it was the same call as
  `get(ini, section, key)` when the default was a string
  ([#16](https://github.com/JuliaIO/IniFile.jl/issues/16)). Use
  `get(defaults(ini), key, default)`.
- `get_bool` accepts 1/yes/true/on and 0/no/false/off (in any case) and
  throws an `ArgumentError` for anything else. It used to return `true` only
  for `true` and `false` for everything else, so `yes`, `on` and `1` now read
  as `true` instead of `false`.
- `get_bool`, `get_int` and `get_float` throw a `KeyError` for a missing key
  (instead of a `MethodError`), and an `ArgumentError` that names the key for a
  value that cannot be parsed.
- `sections(ini)`, `section(ini, name)` and `defaults(ini)` return `OrderedDict`s
  with `String` keys and values instead of `Dict{AbstractString,...}`.
- `show(io, ini)` and `repr(ini)` give a one-line summary such as
  `Inifile(2 sections, 5 keys)`, which is also how an `Inifile` appears inside
  arrays and other containers. `print`, `string` and `write` still give the file
  contents.
- A line indented more than the previous entry is now a continuation of that
  entry's value (previously it was read as a separate entry).
- Malformed lines are reported with `@warn` instead of being printed to
  `stdout`.
- `Inifile` is now an immutable struct created with keyword arguments.
- Julia 1.6 or later is required (0.5 supported Julia 1.0).
