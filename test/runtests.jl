using IniFile
using Test

ini = Inifile()
read(ini, joinpath(dirname(@__FILE__),"test.ini"))

# section exists
@test has_section(ini, "not present") == false
@test has_section(ini, "section 1") == true

# get value or defaults
@test get(ini, "section 1", "strname1") == "section1name1"
@test get(ini, "section 1", "strname2") == "section 1 name 2"
@test get(ini, "section 1", "intname1") == "1"
@test get(ini, "section 1", "floatname1") == "1.1"
@test get(ini, "section 2", "floatname1") == "1.1"
@test get(ini, "section 2", "intname1") == "10"

# int, float and bool types
@test get_int(ini, "section 2", "intname1") == 10
@test get_float(ini, "section 2", "floatname1") == 1.1
@test get_bool(ini, "section 1", "boolname1") == true
@test get_bool(ini, "section 1", "boolname2") == true
@test get_bool(ini, "section 1", "boolname3") == false
@test get_bool(ini, "section 1", "boolname4") == false
@test set(ini, "section 2", "floatname1", 9.1) == 9.1
@test get(ini, "section 2", "floatname1") == 9.1
@test set(ini, "section 2", "intname1", 9) == 9
@test get(ini, "section 2", "intname1") == 9
@test set(ini, "section 2", "boolname1", true) == true
@test get(ini, "section 2", "boolname1") == true
@test set(ini, "section 2", "boolname1", false) == false
@test get(ini, "section 2", "boolname1") == false

# test delimiters
@test get(ini, "section 2", "delimtest1") == "value with :"
@test get(ini, "section 2", "delimtest2") == "name = value"

# key/section not found
@test get(ini, "section 2", "noname") == :notfound
@test get(ini, "section 3", "noname") == :notfound
@test get(ini, "section 3", "noname", nothing) == nothing
@test get(ini, "section 3", "strname1") == "val1"

# create a new section
@test set(ini, "section 3", "strname1", "new string") == "new string"
@test get(ini, "section 3", "strname1") == "new string"
@test get(ini, "section 3", "intname1") == "1"

iob = IOBuffer()
show(iob, ini)
buff = String(take!(iob))

iob = IOBuffer(buff)
ini = Inifile()
read(ini, iob)
@test get(ini, "section 3", "strname1") == "new string"
@test get(ini, "section 3", "intname1") == "1"

