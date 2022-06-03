# IniFile.jl

[![Build Status](https://github.com/JuliaIO/IniFile.jl/workflows/CI/badge.svg)](https://github.com/JuliaIO/IniFile.jl/actions?query=workflows/CI)

Reading and writing Windows-style INI files from Julia

## Usage

```julia
Pkg.add("IniFile") # first-time only
using IniFile # load code into current session
```

#### Create IniFile
```julia
ini = Inifile()
```

#### Get defaults & sections of an IniFile
```julia
sections(ini)
defaults(ini)
```

#### Get specific key from section, return `default` if not found
```julia
get(ini, "section", "key", default)
```

#### Set key for section
```julia
set(ini, "section", "key", value)
```

#### Parse a `*.ini` file
```julia
ini = read(Inifile(), "file.ini")
```

#### Write out a `*.ini` file
```julia
open("file.ini", "w+") do io
    write(io, ini)
end
```

