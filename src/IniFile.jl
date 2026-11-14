"""
    IniFile

Read, query, modify and write INI configuration files.

The parser follows the conventions of Python's `configparser`: `key = value` or
`key: value` entries grouped under `[section]` headers, and full-line comments
starting with `#` or `;`. Sections and keys keep the order in which they were
read or added, so files round-trip through `read` and `write`.

See [`Inifile`](@ref) to get started.
"""
module IniFile

using OrderedCollections: OrderedDict

export Inifile,
       defaults,
       set,
       get_bool,
       get_int,
       get_float,
       has_section,
       section,
       sections

"""
    IniFile.SectionDict

The type of a section: an `OrderedDict{String,String}` mapping keys to values in
the order the keys were first added.
"""
const SectionDict = OrderedDict{String,String}

"""
    Inifile(; lowercase_keys=false, strict=false)

An INI file held in memory: named sections, each mapping keys to string values,
plus a set of default key/value pairs. Sections and keys keep their insertion
order.

Create an empty one with `Inifile()` and fill it with [`read`](@ref) or
[`set`](@ref), or create and read in one step with
`read(Inifile, path_or_io; kwargs...)`. Query it with [`get`](@ref),
[`get_bool`](@ref), [`get_int`](@ref) and [`get_float`](@ref), and save it with
[`write`](@ref).

Key/value pairs that appear before the first section header are stored as
*defaults* (see [`defaults`](@ref)). A lookup in any section falls back to them
when the section does not have the key.

# Keywords
- `lowercase_keys::Bool = false`: store and look up keys in lowercase, so that
  `Key`, `KEY` and `key` are the same key. This matches the default
  `optionxform` of Python's `configparser`. It applies to `read`, `get`, `set`,
  `haskey` and the typed getters. Section names stay case-sensitive.
- `strict::Bool = false`: throw an `ArgumentError` on a malformed line instead
  of logging a warning and skipping it. A line is malformed if it is not blank,
  a comment, a `[section]` header, or a `key = value` or `key: value` entry.

# Examples
```julia-repl
julia> ini = Inifile();

julia> set(ini, "server", "port", 8080)
8080

julia> get(ini, "server", "port")
"8080"

julia> get_int(ini, "server", "port")
8080

julia> ini = read(Inifile, "config.ini"; lowercase_keys=true);
```
"""
struct Inifile
    sections::OrderedDict{String,SectionDict}
    defaults::SectionDict
    lowercase_keys::Bool
    strict::Bool
end

Inifile(; lowercase_keys::Bool=false, strict::Bool=false) =
    Inifile(OrderedDict{String,SectionDict}(), SectionDict(), lowercase_keys, strict)

# Normalize a key to the form in which it is stored.
_key(ini::Inifile, key::AbstractString) = ini.lowercase_keys ? lowercase(key) : String(key)

"""
    defaults(ini::Inifile) -> OrderedDict{String,String}

Return the default key/value pairs of `ini`: those that appear before the first
section header in a file, or that were added with `set(ini, key, value)`.

The returned dictionary is the one stored in `ini`, so modifying it modifies
`ini`. Keys added to it directly are not lowercased, even when `ini` was created
with `lowercase_keys=true`.
"""
defaults(ini::Inifile) = ini.defaults

"""
    sections(ini::Inifile) -> OrderedDict{String,OrderedDict{String,String}}

Return the sections of `ini`, mapping each section name to its key/value pairs,
in the order the sections were first read or added. The defaults are not
included; see [`defaults`](@ref).

The returned dictionary is the one stored in `ini`, so modifying it modifies
`ini`.
"""
sections(ini::Inifile) = ini.sections

"""
    has_section(ini::Inifile, name::AbstractString) -> Bool

Return whether `ini` has a section called `name`.
"""
has_section(ini::Inifile, name::AbstractString) = haskey(ini.sections, name)

"""
    section(ini::Inifile, name::AbstractString) -> OrderedDict{String,String}

Return the key/value pairs of the section called `name`, or throw a `KeyError`
if there is no such section. Defaults are not merged in.

The returned dictionary is the one stored in `ini`, so modifying it modifies
`ini`.
"""
section(ini::Inifile, name::AbstractString) = ini.sections[name]

"""
    haskey(ini::Inifile, section::AbstractString, key::AbstractString) -> Bool

Return whether the section `section` exists and contains `key`. Unlike
[`get`](@ref), this does not look in the defaults.
"""
function Base.haskey(ini::Inifile, section::AbstractString, key::AbstractString)
    sec = get(ini.sections, section, nothing)
    return sec !== nothing && haskey(sec, _key(ini, key))
end

#
# Reading
#

"""
    read(ini::Inifile, io::IO) -> ini
    read(ini::Inifile, filename::AbstractString) -> ini
    read(Inifile, io_or_filename; kwargs...) -> Inifile

Parse INI text from a stream or a file into `ini` and return `ini`. The last
form creates a new [`Inifile`](@ref), passing the keyword arguments
(`lowercase_keys`, `strict`) to its constructor.

Reading into an `Inifile` that already has content merges the new content in:
sections that appear again are extended, and keys that appear again are
overwritten.

# Syntax
- Blank lines are ignored.
- Lines whose first non-blank character is `#` or `;` are comments.
- `[name]` starts a section called `name`. Entries before the first section
  header go to the defaults.
- `key = value` or `key: value` sets a key; the first `=` or `:` on the line is
  the delimiter. Whitespace around the key and the value is removed. The value
  may be empty, as in `key =`.
- A UTF-8 byte order mark at the start of the input is ignored, and both `\\n`
  and `\\r\\n` line endings are accepted.

Any other line is malformed. It is skipped with a warning that gives its line
number or, if `ini` was created with `strict=true`, an `ArgumentError` is thrown
and `ini` is left partially read.

# Examples
```julia-repl
julia> ini = read(Inifile, IOBuffer(\"\"\"
           [paths]
           data = /srv/data
           \"\"\"));

julia> get(ini, "paths", "data")
"/srv/data"
```
"""
Base.read(ini::Inifile, io::IO) = _parse!(ini, io, nothing)

Base.read(ini::Inifile, filename::AbstractString) =
    open(io -> _parse!(ini, io, String(filename)), filename)

Base.read(::Type{Inifile}, src::Union{IO,AbstractString}; kwargs...) =
    read(Inifile(; kwargs...), src)

function _parse!(ini::Inifile, io::IO, source::Union{String,Nothing})
    sec = ini.defaults         # section that receives new entries
    for (lineno, line) in enumerate(eachline(io))
        if lineno == 1 && startswith(line, '\ufeff')
            line = String(chop(line; head=1, tail=0))
        end
        text = strip(line)
        if isempty(text) || startswith(text, '#') || startswith(text, ';')
            continue
        elseif startswith(text, '[') && endswith(text, ']') && ncodeunits(text) > 2
            sec = get!(SectionDict, ini.sections, String(chop(text; head=1, tail=1)))
        else
            i = findfirst(c -> c == '=' || c == ':', text)
            k = i === nothing ? "" : rstrip(SubString(text, 1, prevind(text, i)))
            if isempty(k)
                _malformed(ini, source, lineno, line)
                continue
            end
            sec[_key(ini, k)] = String(lstrip(SubString(text, nextind(text, i))))
        end
    end
    return ini
end

function _malformed(ini::Inifile, source, lineno::Int, line::AbstractString)
    location = source === nothing ? "line $lineno" : "line $lineno of $source"
    msg = "malformed $location: $(repr(String(line))); expected `[section]`, `key = value` or `key: value`"
    ini.strict && throw(ArgumentError(msg))
    @warn "Skipping $msg"
    return nothing
end

#
# Writing and display
#

"""
    write(io::IO, ini::Inifile) -> Int
    write(filename::AbstractString, ini::Inifile) -> Int

Write `ini` in INI format and return the number of bytes written. Defaults come
first, then each section in order, separated by blank lines. Entries are written
as `key = value`.

# Examples
```julia-repl
julia> ini = Inifile();

julia> set(ini, "b", "x", 1); set(ini, "a", "y", "two");

julia> write(stdout, ini);
[b]
x = 1

[a]
y = two
```
"""
function Base.write(io::IO, ini::Inifile)
    buf = IOBuffer()
    _write_entries(buf, ini.defaults)
    for (name, sec) in ini.sections
        position(buf) > 0 && println(buf)
        println(buf, '[', name, ']')
        _write_entries(buf, sec)
    end
    return write(io, take!(buf))
end

function _write_entries(io::IO, sec::SectionDict)
    for (key, value) in sec
        isempty(value) ? println(io, key, " =") : println(io, key, " = ", value)
    end
end

_plural(n::Int, word::String) = n == 1 ? "1 $word" : "$n $(word)s"

# Compact form, used by `print`, `string` and when shown inside containers.
function Base.show(io::IO, ini::Inifile)
    nkeys = length(ini.defaults) + sum(length, values(ini.sections); init=0)
    print(io, "Inifile(", _plural(length(ini.sections), "section"), ", ",
          _plural(nkeys, "key"), ")")
end

# Full form, used by the REPL: a summary line followed by the file contents.
function Base.show(io::IO, ::MIME"text/plain", ini::Inifile)
    show(io, ini)
    text = sprint(write, ini)
    isempty(text) || print(io, ":\n", chomp(text))
end

#
# Getting and setting values
#

"""
    get(ini::Inifile, section::AbstractString, key::AbstractString, default=nothing)

Return the value of `key` in `section` as a `String`. If the section does not
have the key, look in the defaults; if the key is not there either, return
`default`.

See also [`get_bool`](@ref), [`get_int`](@ref) and [`get_float`](@ref).
"""
function Base.get(ini::Inifile, section::AbstractString, key::AbstractString, default)
    k = _key(ini, key)
    sec = get(ini.sections, section, nothing)
    if sec !== nothing
        value = get(sec, k, nothing)
        value === nothing || return value
    end
    return get(ini.defaults, k, default)
end

Base.get(ini::Inifile, section::AbstractString, key::AbstractString) =
    get(ini, section, key, nothing)

"""
    get(ini::Inifile, key::AbstractString)

Return the value of `key` in the defaults as a `String`, or `nothing` if there is
no such key.

There is no method taking a default value, because `get(ini, key, default)`
would be the same call as `get(ini, section, key)`. Use
`get(defaults(ini), key, default)` instead.
"""
Base.get(ini::Inifile, key::AbstractString) = get(ini.defaults, _key(ini, key), nothing)

"""
    set(ini::Inifile, section::AbstractString, key::AbstractString, value) -> value
    set(ini::Inifile, key::AbstractString, value) -> value

Set `key` to `value` in `section`, creating the section if needed, and return
`value`. Without a section, set `key` in the defaults.

`value` may be a string, a number or a `Bool`. It is stored as `string(value)`,
so [`get`](@ref) always returns a `String`; read it back with
[`get_int`](@ref), [`get_float`](@ref) or [`get_bool`](@ref) to get a number or
a `Bool`. If `value` is `nothing`, the key is removed instead (and a missing
section is not created).
"""
function set(ini::Inifile, section::AbstractString, key::AbstractString,
             value::Union{AbstractString,Number,Nothing})
    if value === nothing
        sec = get(ini.sections, section, nothing)
        sec === nothing || delete!(sec, _key(ini, key))
    else
        get!(SectionDict, ini.sections, String(section))[_key(ini, key)] = string(value)
    end
    return value
end

function set(ini::Inifile, key::AbstractString, value::Union{AbstractString,Number,Nothing})
    if value === nothing
        delete!(ini.defaults, _key(ini, key))
    else
        ini.defaults[_key(ini, key)] = string(value)
    end
    return value
end

function _require(ini::Inifile, section::AbstractString, key::AbstractString)
    value = get(ini, section, key)
    value === nothing && throw(KeyError((String(section), String(key))))
    return value
end

const _BOOLEANS = Dict("1" => true, "yes" => true, "true" => true, "on" => true,
                       "0" => false, "no" => false, "false" => false, "off" => false)

function _parse_bool(value::AbstractString, section::AbstractString, key::AbstractString)
    b = get(_BOOLEANS, lowercase(strip(value)), nothing)
    b === nothing && throw(ArgumentError(
        "value $(repr(value)) of key $(repr(key)) in section $(repr(section)) is not a boolean; " *
        "expected 1, yes, true, on, 0, no, false or off (in any letter case)"))
    return b
end

function _parse_number(::Type{T}, value::AbstractString, section::AbstractString,
                       key::AbstractString) where {T<:Real}
    x = tryparse(T, value)
    x === nothing && throw(ArgumentError(
        "value $(repr(value)) of key $(repr(key)) in section $(repr(section)) is not a valid $T"))
    return x
end

"""
    get_bool(ini::Inifile, section::AbstractString, key::AbstractString[, default])

Return the value of `key` in `section` (or in the defaults) as a `Bool`. As in
Python's `configparser`, `1`, `yes`, `true` and `on` mean `true`, and `0`, `no`,
`false` and `off` mean `false`, in any letter case. Any other value throws an
`ArgumentError` that names the section, key and value.

If the key is missing, return `default`, or throw a `KeyError` if no default is
given.
"""
get_bool(ini::Inifile, section::AbstractString, key::AbstractString) =
    _parse_bool(_require(ini, section, key), section, key)

function get_bool(ini::Inifile, section::AbstractString, key::AbstractString, default)
    value = get(ini, section, key)
    return value === nothing ? default : _parse_bool(value, section, key)
end

"""
    get_int(ini::Inifile, section::AbstractString, key::AbstractString[, default])

Return the value of `key` in `section` (or in the defaults) parsed as an `Int`.
A value that cannot be parsed throws an `ArgumentError` that names the section,
key and value.

If the key is missing, return `default`, or throw a `KeyError` if no default is
given.
"""
get_int(ini::Inifile, section::AbstractString, key::AbstractString) =
    _parse_number(Int, _require(ini, section, key), section, key)

function get_int(ini::Inifile, section::AbstractString, key::AbstractString, default)
    value = get(ini, section, key)
    return value === nothing ? default : _parse_number(Int, value, section, key)
end

"""
    get_float(ini::Inifile, section::AbstractString, key::AbstractString[, default])

Return the value of `key` in `section` (or in the defaults) parsed as a
`Float64`. A value that cannot be parsed throws an `ArgumentError` that names
the section, key and value.

If the key is missing, return `default`, or throw a `KeyError` if no default is
given.
"""
get_float(ini::Inifile, section::AbstractString, key::AbstractString) =
    _parse_number(Float64, _require(ini, section, key), section, key)

function get_float(ini::Inifile, section::AbstractString, key::AbstractString, default)
    value = get(ini, section, key)
    return value === nothing ? default : _parse_number(Float64, value, section, key)
end

end # module
