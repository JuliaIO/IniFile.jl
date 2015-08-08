using IniFile
using Base.Test

ini = Inifile()
read(ini, "test.ini")

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

# test comments mid-line
ini2 = Inifile()
read(ini2, "test.ini", true)
@test get(ini, "section 4", "midline") != "value"
@test get(ini2, "section 4", "midline") == "value"

# test multi-line values
val = get(ini, "section 4", "multiline1")
@test val != :notfound
@test length(val) >= 30 && val[end] == '.'

# test multi-line value with comment midline
val = get(ini, "section 4", "multiline2")
@test val != :notfound
@test length(val) >= 25 && val[end] == '.'
val = get(ini2, "section 4", "multiline2")
@test val != :notfound
@test length(val) >= 25 && val[end] == 't'


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
buff = takebuf_string(iob)

iob = IOBuffer(buff)
ini = Inifile()
read(ini, iob)
@test get(ini, "section 3", "strname1") == "new string"
@test get(ini, "section 3", "intname1") == "1"
