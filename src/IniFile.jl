module Inifile
using Base

import Base.get,
       Base.has,
       Base.read,
       Base.show

export IniFile,
       defaults,
       get,
       get_bool,
       has,
       has_section,
       read,
       section,
       sections,
       show

typealias HTSS Dict{String,String}

type IniFile
    sections::Dict{String,HTSS}
    defaults::HTSS
end

IniFile() = IniFile((String=>HTSS)[], HTSS())

defaults(inifile::IniFile) = inifile.defaults

sections(inifile::IniFile) = inifile.sections

function read(inifile::IniFile, stream::IOStream)
    current_section = inifile.defaults
    for line in EachLine(stream)
        s = strip(line)
        # comments start with # or ;
        if length(s) < 3 || s[1] == '#' || s[1] == ';'
            continue
        elseif s[1] == '[' && s[end] == ']'
            section = s[2:end-1]
            if !has(inifile.sections, section)
                inifile.sections[section] = HTSS()
            end
            current_section = inifile.sections[section]
        else
            i = strchr(s, '=')
            j = strchr(s, ':')
            if i == 0 && j == 0
                # TODO: allow multiline values
                println("skipping malformed line: $s")
            else
                idx = min(i, j)
                if idx == 0
                    idx = max(i, j)
                end
                key = rstrip(s[1:idx-1])
                val = lstrip(s[idx+1:end])
                current_section[key] = val
            end
        end
    end
    inifile
end

function read(inifile::IniFile, filename::String)
    f = open(filename)
    read(inifile, f)
    close(f)
    inifile
end

function show(io::IO, inifile::IniFile)
    for (key, value) in defaults(inifile)
        println(io, "$key=$value")
    end
    for (name, htss) in sections(inifile)
        println(io, "[$name]")
        for (key, value) in htss
            println(io, "$key=$value")
        end
    end
end

get(inifile::IniFile, section::String, key::String) = get(inifile, section, key, :notfound)

function get(inifile::IniFile, section::String, key::String, notfound)
    if has(inifile.sections, section) && has(inifile.sections[section], key)
        return inifile.sections[section][key]
    elseif has(inifile.defaults, key)
        return inifile.defaults[key]
    end
    notfound
end

get_bool(inifile::IniFile, section::String, key::String) = 
    get(inifile, section, key) == "true"

has(inifile::IniFile, section::String, key::String) =
    has(inifile.sections, section) && has(inifile.sections[section], key)

has_section(inifile::IniFile, section::String) = has(inifile.sections, section)

section(inifile::IniFile, section::String) = inifile.sections[section]

end # module
