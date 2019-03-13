# IniFile.jl

[![IniFile](http://pkg.julialang.org/badges/IniFile_0.4.svg)](http://pkg.julialang.org/?pkg=IniFile)
[![IniFile](http://pkg.julialang.org/badges/IniFile_0.5.svg)](http://pkg.julialang.org/?pkg=IniFile)
[![IniFile](http://pkg.julialang.org/badges/IniFile_0.6.svg)](http://pkg.julialang.org/?pkg=IniFile)
[![Build Status](https://travis-ci.org/JuliaIO/IniFile.jl.svg?branch=master)](https://travis-ci.org/JuliaIO/IniFile.jl)

Reading and writing Windows-style INI files from Julia

## Usage

```julia
Pkg.add("IniFile") # first-time only
using Inifile # load code into current session
```

#### Create IniFile
```julia
ini = IniFile()
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

