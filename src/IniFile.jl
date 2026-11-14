"""
    IniFile

Read, query, modify and write INI configuration files.

The parser follows the conventions of Python's `configparser`: `key = value` or
`key: value` entries grouped under `[section]` headers, full-line comments
starting with `#` or `;`, and, when enabled with `multiline_values=true`,
multi-line values written as indented continuation lines. Sections and keys keep
the order in which they were read or added, so files round-trip through `read`
and `write`.

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
       merged,
       section,
       sections

"""
    IniFile.SectionDict

The type of a section: an `OrderedDict{String,String}` mapping keys to values in
the order the keys were first added.
"""
const SectionDict = OrderedDict{String,String}

"""
    Inifile(; lowercase_keys=false, inline_comment_prefixes=(), multiline_values=false, strict=false)

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
- `inline_comment_prefixes = ()`: strings or characters that start a comment
  in the middle of a line, such as `(";", "#")`. A prefix only starts a comment
  at the beginning of a line or after whitespace, so `a = b;c` keeps its `;`.
  Inline comments are off by default, as in Python 3's `configparser`, because
  values may legitimately contain `;` or `#`.
- `multiline_values::Bool = false`: allow values that span several lines. A
  line indented more than the line that started an entry then continues that
  entry's value, as in Python's `configparser`. When `false`, every line stands
  on its own and leading whitespace is ignored, as in IniFile 0.5, and
  [`write`](@ref) throws for a value that contains a newline, because it could
  not be read back.
- `strict::Bool = false`: throw an `ArgumentError` on a malformed line instead
  of logging a warning and skipping it. A line is malformed if it is not blank,
  a comment, a `[section]` header, a `key = value` or `key: value` entry, or,
  with `multiline_values=true`, a continuation line. `strict` does not affect
  repeated keys or sections, which are always allowed (see [`read`](@ref)).

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
    inline_comment_prefixes::Vector{String}
    multiline_values::Bool
    strict::Bool
end

function Inifile(; lowercase_keys::Bool=false, inline_comment_prefixes=(),
                 multiline_values::Bool=false, strict::Bool=false)
    prefixes = String[string(p) for p in inline_comment_prefixes]
    any(isempty, prefixes) && throw(ArgumentError("inline comment prefixes must not be empty"))
    return Inifile(OrderedDict{String,SectionDict}(), SectionDict(), lowercase_keys, prefixes,
                   multiline_values, strict)
end

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
    merged(ini::Inifile) -> OrderedDict{String,String}

Return the keys of `ini` from the defaults and from all sections in one
dictionary. The defaults come first, then the keys of each section, with the
sections in order. When a key appears in more than one place, the later one
wins: a key in a section overrides the same key in the defaults, and a key in a
later section overrides the same key in an earlier section. Each key keeps the
position where it first appeared.

Sections are ordered by where their header first appears, and a header that
appears again adds to the earlier section (see [`read`](@ref)). So a key in a
later section wins even over a line further down the file that is in a repeated,
earlier section. For a file without a `[DEFAULT]` section, this gives the same
values as reading it with Python 2's `ConfigParser` (or Python 3's
`configparser` with `strict=False`) and collecting the items of each section, in
order, into one dictionary.

The result is a new dictionary: changing it does not change `ini`.

# Examples
```julia-repl
julia> ini = read(Inifile, IOBuffer(\"\"\"
           solver = cg+amg
           [options]
           solver = cholmod
           [output]
           write_maps = true
           \"\"\"));

julia> merged(ini)["solver"]
"cholmod"

julia> collect(keys(merged(ini)))
2-element Vector{String}:
 "solver"
 "write_maps"
```
"""
function merged(ini::Inifile)
    result = copy(ini.defaults)
    for sec in values(ini.sections)
        merge!(result, sec)
    end
    return result
end

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
(`lowercase_keys`, `inline_comment_prefixes`, `multiline_values`, `strict`) to
its constructor.

Reading into an `Inifile` that already has content merges the new content in,
in the same way as repeated sections and keys within one file (see below).

# Syntax
- Blank lines are ignored, except inside a multi-line value.
- Lines whose first non-blank character is `#` or `;` are comments.
- `[name]` starts a section called `name`. Entries before the first section
  header go to the defaults.
- `key = value` or `key: value` sets a key; the first `=` or `:` on the line is
  the delimiter. Whitespace around the key and the value is removed. The value
  may be empty, as in `key =`.
- Leading whitespace is ignored, unless `ini` was created with
  `multiline_values=true`. Then a line indented more than the line that started
  the current entry continues its value. The lines of a value are joined with
  `"\\n"`, blank lines inside the value are kept, and trailing blank lines are
  dropped. Comment lines inside a value are skipped.
- Inline comments are recognized only if `ini` was created with
  `inline_comment_prefixes`.
- A UTF-8 byte order mark at the start of the input is ignored, and both `\\n`
  and `\\r\\n` line endings are accepted.

Any other line is malformed. It is skipped with a warning that gives its line
number or, if `ini` was created with `strict=true`, an `ArgumentError` is thrown
and `ini` is left partially read.

# Repeated keys and sections
- A key that appears again in the same section replaces the earlier value, and
  keeps the position where it first appeared. The last value wins.
- A section header that appears again does not start a new section. The entries
  that follow it are added to the earlier section, which keeps the position of
  its first header.
- Repeated keys and sections are never an error, even with `strict=true`.

[`merged`](@ref) combines the defaults and all sections into one dictionary, in
which a key in a later section overrides the same key in an earlier one.

# Examples
```julia-repl
julia> ini = read(Inifile, IOBuffer(\"\"\"
           [paths]
           data = /srv/data
           search =
               /usr/lib
               /opt/lib
           \"\"\"); multiline_values=true);

julia> get(ini, "paths", "data")
"/srv/data"

julia> get(ini, "paths", "search")
"\\n/usr/lib\\n/opt/lib"
```
"""
Base.read(ini::Inifile, io::IO) = _parse!(ini, io, nothing)

Base.read(ini::Inifile, filename::AbstractString) =
    open(io -> _parse!(ini, io, String(filename)), filename)

Base.read(::Type{Inifile}, src::Union{IO,AbstractString}; kwargs...) =
    read(Inifile(; kwargs...), src)

function _parse!(ini::Inifile, io::IO, source::Union{String,Nothing})
    sec = ini.defaults         # section that receives new entries
    key = nothing              # key of the entry whose value may still continue
    value = String[]           # lines of that value so far
    indent = 0                 # indentation of the line that started the entry
    for (lineno, line) in enumerate(eachline(io))
        if lineno == 1 && startswith(line, '\ufeff')
            line = String(chop(line; head=1, tail=0))
        end
        stripped = strip(line)
        # full-line comments are skipped; they do not end a multi-line value
        if startswith(stripped, '#') || startswith(stripped, ';')
            continue
        end
        text = strip(_strip_inline_comment(line, ini.inline_comment_prefixes))
        if isempty(text)
            # a blank line may be part of a multi-line value, a comment is not
            ini.multiline_values && key !== nothing && isempty(stripped) && push!(value, "")
            continue
        end
        ind = something(findfirst(!isspace, line), 1)
        if ini.multiline_values && key !== nothing && ind > indent
            push!(value, text)
            continue
        end
        # this line starts something new, so the previous value is complete
        key === nothing || (sec[key] = _joinvalue(value))
        key = nothing
        indent = ind
        if startswith(text, '[') && endswith(text, ']') && ncodeunits(text) > 2
            sec = get!(SectionDict, ini.sections, String(chop(text; head=1, tail=1)))
        else
            i = findfirst(c -> c == '=' || c == ':', text)
            k = i === nothing ? "" : rstrip(SubString(text, 1, prevind(text, i)))
            if isempty(k)
                _malformed(ini, source, lineno, line)
                continue
            end
            key = _key(ini, k)
            empty!(value)
            push!(value, String(lstrip(SubString(text, nextind(text, i)))))
        end
    end
    key === nothing || (sec[key] = _joinvalue(value))
    return ini
end

_joinvalue(lines::Vector{String}) = String(rstrip(join(lines, '\n')))

# Cut `line` at the earliest inline comment prefix that starts the line or
# follows whitespace, as Python's configparser does.
function _strip_inline_comment(line::AbstractString, prefixes::Vector{String})
    isempty(prefixes) && return line
    cut = 0
    for prefix in prefixes
        r = findfirst(prefix, line)
        while r !== nothing
            i = first(r)
            if i == 1 || isspace(line[prevind(line, i)])
                cut = cut == 0 ? i : min(cut, i)
                break
            end
            r = findnext(prefix, line, nextind(line, i))
        end
    end
    return cut == 0 ? line : SubString(line, 1, prevind(line, cut))
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

If `ini` was created with `multiline_values=true`, a value that contains
newlines is written as continuation lines indented with a tab, so that
[`read`](@ref) restores it. Otherwise such a value could not be read back, so
`write` throws an `ArgumentError` that names its key and section, before
anything is written.

`print(io, ini)` and `string(ini)` also give the file contents.

# Examples
```julia-repl
julia> ini = Inifile(multiline_values=true);

julia> set(ini, "b", "x", 1); set(ini, "a", "y", "two\\nlines");

julia> write(stdout, ini);
[b]
x = 1

[a]
y = two
	lines
```
"""
function Base.write(io::IO, ini::Inifile)
    _check_writable(ini)
    return write(io, _contents(ini))
end

# Check before opening the file, so that an error does not leave it empty.
function Base.write(filename::AbstractString, ini::Inifile)
    _check_writable(ini)
    return open(io -> write(io, _contents(ini)), filename, "w")
end

# Throw if `ini` has a value that `read` could not restore from the written text.
function _check_writable(ini::Inifile)
    ini.multiline_values && return nothing
    _check_single_line(ini.defaults, nothing)
    for (name, sec) in ini.sections
        _check_single_line(sec, name)
    end
    return nothing
end

function _check_single_line(sec::SectionDict, name::Union{String,Nothing})
    for (key, value) in sec
        occursin('\n', value) || continue
        where = name === nothing ? "the defaults" : "section $(repr(name))"
        throw(ArgumentError(
            "cannot write key $(repr(key)) in $where: its value spans several lines, " *
            "which can only be written by an Inifile created with multiline_values=true"))
    end
end

# The INI text of `ini`, as bytes.
function _contents(ini::Inifile)
    buf = IOBuffer()
    _write_entries(buf, ini.defaults)
    for (name, sec) in ini.sections
        position(buf) > 0 && println(buf)
        println(buf, '[', name, ']')
        _write_entries(buf, sec)
    end
    return take!(buf)
end

function _write_entries(io::IO, sec::SectionDict)
    for (key, value) in sec
        lines = split(value, '\n')
        print(io, key, " =")
        isempty(lines[1]) || print(io, ' ', lines[1])
        for line in @view lines[2:end]
            println(io)
            isempty(line) || print(io, '\t', line)
        end
        println(io)
    end
end

_plural(n::Int, word::String) = n == 1 ? "1 $word" : "$n $(word)s"

# `print` and `string` give the file contents, as they did in IniFile 0.5.
Base.print(io::IO, ini::Inifile) = (write(io, ini); nothing)

# Compact form, used when shown inside containers and by `repr`.
function Base.show(io::IO, ini::Inifile)
    nkeys = length(ini.defaults) + sum(length, values(ini.sections); init=0)
    print(io, "Inifile(", _plural(length(ini.sections), "section"), ", ",
          _plural(nkeys, "key"), ")")
end

# Full form, used by the REPL: a summary line followed by the file contents.
function Base.show(io::IO, ::MIME"text/plain", ini::Inifile)
    show(io, ini)
    # unlike `write`, display never throws, even for values that span several lines
    text = String(_contents(ini))
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
section is not created). Setting an existing key keeps its position.

A value that contains newlines can be set, but only an `Inifile` created with
`multiline_values=true` can [`write`](@ref) it.
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
