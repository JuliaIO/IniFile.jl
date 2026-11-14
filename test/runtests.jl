using IniFile
using Test
using Aqua

const TESTINI = joinpath(@__DIR__, "test.ini")

parse_ini(text; kwargs...) = read(Inifile, IOBuffer(text); kwargs...)
ini_string(ini) = sprint(write, ini)
# Contents with order, so that comparisons are order-sensitive.
contents(ini) = (collect(defaults(ini)), [name => collect(sec) for (name, sec) in sections(ini)])

@testset "IniFile" begin

@testset "test.ini" begin
    ini = Inifile()
    @test read(ini, TESTINI) === ini

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
    @test get(ini, "strname1") == "val1"

    # int, float and bool types
    @test get_int(ini, "section 2", "intname1") === 10
    @test get_float(ini, "section 2", "floatname1") === 1.1
    @test get_bool(ini, "section 1", "boolname1") === true
    @test get_bool(ini, "section 1", "boolname2") === true
    @test get_bool(ini, "section 1", "boolname3") === false
    @test get_bool(ini, "section 1", "boolname4") === false

    # set stores the string form of the value
    @test set(ini, "section 2", "floatname1", 9.1) == 9.1
    @test get(ini, "section 2", "floatname1") == "9.1"
    @test get_float(ini, "section 2", "floatname1") === 9.1
    @test set(ini, "section 2", "intname1", 9) == 9
    @test get(ini, "section 2", "intname1") == "9"
    @test get_int(ini, "section 2", "intname1") === 9
    @test set(ini, "section 2", "boolname1", true) == true
    @test get(ini, "section 2", "boolname1") == "true"
    @test get_bool(ini, "section 2", "boolname1") === true
    @test set(ini, "section 2", "boolname1", false) == false
    @test get(ini, "section 2", "boolname1") == "false"
    @test get_bool(ini, "section 2", "boolname1") === false

    # delimiters
    @test get(ini, "section 2", "delimtest1") == "value with :"
    @test get(ini, "section 2", "delimtest2") == "name = value"

    # key/section not found
    @test get(ini, "section 2", "noname") === nothing
    @test get(ini, "section 3", "noname") === nothing
    @test get(ini, "section 3", "noname", "default") == "default"
    @test get(ini, "section 3", "strname1") == "val1"

    # create a new section
    @test set(ini, "section 3", "strname1", "new string") == "new string"
    @test get(ini, "section 3", "strname1") == "new string"
    @test get(ini, "section 3", "intname1") == "1"

    # multi-line values and mid-line comments (adapted from #10)
    @test get(ini, "section 4", "midline") == "value ; comment"
    @test get(ini, "section 4", "multiline1") == "This is multiple\nlines of text"
    @test get(ini, "section 4", "multiline2") ==
          "This is multiple\nlines of text that ; should be\nformed into a single value ; and a comment"
    ini2 = read(Inifile, TESTINI; inline_comment_prefixes=(";",))
    @test get(ini2, "section 4", "midline") == "value"
    @test get(ini2, "section 4", "multiline2") ==
          "This is multiple\nlines of text that\nformed into a single value"

    # round trip through write
    ini2 = parse_ini(ini_string(ini))
    @test contents(ini2) == contents(ini)
    @test get(ini2, "section 3", "strname1") == "new string"
    @test get(ini2, "section 3", "intname1") == "1"
end

@testset "short lines are not skipped" begin
    ini = parse_ini("""
        a=
        b=1
        [s]
        c:
        d=x
        """)
    @test get(ini, "a") == ""
    @test get(ini, "b") == "1"
    @test has_section(ini, "s")
    @test get(ini, "s", "c") == ""
    @test get(ini, "s", "d") == "x"
    @test collect(keys(section(ini, "s"))) == ["c", "d"]
end

@testset "blank lines and comments" begin
    ini = parse_ini("""

        # comment
        ; comment
            # indented comment
        [s]

        a = 1
        ;a = 2
        #a = 3
        """)
    @test contents(ini) == ([], ["s" => ["a" => "1"]])
end

@testset "malformed lines" begin
    text = """
        [s]
        a = 1
        not an entry
        []
        = value
        [unterminated
        b = 2
        """
    ini = @test_logs((:warn, r"line 3: \"not an entry\""),
                     (:warn, r"line 4: \"\[\]\""),
                     (:warn, r"line 5: \"= value\""),
                     (:warn, r"line 6: \"\[unterminated\""),
                     parse_ini(text))
    @test contents(ini) == ([], ["s" => ["a" => "1", "b" => "2"]])

    err = @test_throws ArgumentError parse_ini(text; strict=true)
    @test occursin("line 3", err.value.msg)
    @test occursin("not an entry", err.value.msg)

    # the file name is part of the message
    path = joinpath(mktempdir(), "bad.ini")
    write(path, text)
    @test_logs (:warn, r"line 3 of .*bad\.ini") match_mode=:any read(Inifile, path)
    @test_throws ArgumentError read(Inifile, path; strict=true)

    # nothing is printed to stdout
    printed = mktemp() do file, io
        redirect_stdout(io) do
            @test_logs (:warn,) parse_ini("junk")
        end
        flush(io)
        read(file, String)
    end
    @test isempty(printed)
end

@testset "delimiters" begin
    ini = parse_ini("""
        [s]
        a = b:c
        d : e=f
        url = http://example.com/?q=1
        time: 12:30
        k=v=w
        spaced key   =   spaced value
        """)
    @test get(ini, "s", "a") == "b:c"
    @test get(ini, "s", "d") == "e=f"
    @test get(ini, "s", "url") == "http://example.com/?q=1"
    @test get(ini, "s", "time") == "12:30"
    @test get(ini, "s", "k") == "v=w"
    @test get(ini, "s", "spaced key") == "spaced value"
end

@testset "line endings and byte order mark" begin
    ini = parse_ini("﻿[s]\r\na = 1\r\nb = 2\r\n")
    @test contents(ini) == ([], ["s" => ["a" => "1", "b" => "2"]])
    ini = parse_ini("﻿a = 1\n")
    @test get(ini, "a") == "1"
end

@testset "keys are case-sensitive by default" begin
    ini = parse_ini("[S]\nKey = 1\n")
    @test get(ini, "S", "Key") == "1"
    @test get(ini, "S", "key") === nothing
    @test !haskey(ini, "S", "key")
    @test !has_section(ini, "s")
end

@testset "lowercase_keys" begin
    text = """
        Top = 1
        [Section]
        MixedCase = a
        UPPER: b
        Flag = Yes
        """
    ini = parse_ini(text; lowercase_keys=true)
    @test collect(keys(defaults(ini))) == ["top"]
    @test collect(keys(section(ini, "Section"))) == ["mixedcase", "upper", "flag"]
    @test get(ini, "Section", "MIXEDCASE") == "a"
    @test get(ini, "Section", "upper") == "b"
    @test get(ini, "Section", "TOP") == "1"
    @test get(ini, "tOp") == "1"
    @test haskey(ini, "Section", "Upper")
    @test get_bool(ini, "Section", "FLAG") === true
    # section names stay case-sensitive
    @test has_section(ini, "Section")
    @test !has_section(ini, "section")

    @test set(ini, "Section", "NewKey", 1) == 1
    @test haskey(section(ini, "Section"), "newkey")
    @test get_int(ini, "Section", "NEWKEY") === 1
    set(ini, "Section", "NEWKEY", nothing)
    @test !haskey(ini, "Section", "newkey")
    set(ini, "TOP", 2)
    @test collect(defaults(ini)) == ["top" => "2"]
    set(ini, "Top", nothing)
    @test isempty(defaults(ini))
end

@testset "order is preserved" begin
    text = """
        zeta = 1
        alpha = 2

        [zulu]
        z = 1
        y = 2
        x = 3

        [alpha]
        c = 3
        b = 2
        a = 1

        [mike]
        """
    ini = parse_ini(text)
    @test collect(keys(defaults(ini))) == ["zeta", "alpha"]
    @test collect(keys(sections(ini))) == ["zulu", "alpha", "mike"]
    @test collect(keys(section(ini, "zulu"))) == ["z", "y", "x"]
    @test isempty(section(ini, "mike"))
    # the text is already in the format that write produces
    @test ini_string(ini) == text

    # setting an existing key keeps its place; new keys and sections go last
    set(ini, "zulu", "y", 20)
    set(ini, "zulu", "w", 4)
    set(ini, "bravo", "k", "v")
    @test collect(section(ini, "zulu")) == ["z" => "1", "y" => "20", "x" => "3", "w" => "4"]
    @test collect(keys(sections(ini))) == ["zulu", "alpha", "mike", "bravo"]

    # repeated keys and sections: first position, last value
    ini = parse_ini("""
        [a]
        x = 1
        y = 2
        [b]
        z = 3
        [a]
        x = 10
        w = 4
        """)
    @test contents(ini) == ([], ["a" => ["x" => "10", "y" => "2", "w" => "4"], "b" => ["z" => "3"]])
end

@testset "write" begin
    ini = parse_ini("""
        # comments are not kept
        top=1
        [first]
        a=1
        b :2
        [second]
        c=
        """)
    expected = """
        top = 1

        [first]
        a = 1
        b = 2

        [second]
        c =
        """
    @test ini_string(ini) == expected
    @test ini_string(parse_ini(expected)) == expected
    @test write(IOBuffer(), ini) == sizeof(expected)

    # no defaults: no leading blank line
    ini = Inifile()
    set(ini, "s", "k", "v")
    @test ini_string(ini) == "[s]\nk = v\n"
    @test ini_string(Inifile()) == ""

    # write to a file name
    path = joinpath(mktempdir(), "out.ini")
    @test write(path, ini) == filesize(path)
    @test read(path, String) == "[s]\nk = v\n"
end

@testset "multi-line values" begin
    text = """
        [s]
        key1 = first line
            second line
        \tthird line
        key2 = single
        key3 =
            a
            b
        key4 = paragraph one

            paragraph two

        key5 = with comments
            # not part of the value
            ; nor this
            continued
        next = 1
        """
    ini = parse_ini(text)
    @test get(ini, "s", "key1") == "first line\nsecond line\nthird line"
    @test get(ini, "s", "key2") == "single"
    @test get(ini, "s", "key3") == "\na\nb"
    @test get(ini, "s", "key4") == "paragraph one\n\nparagraph two"
    @test get(ini, "s", "key5") == "with comments\ncontinued"
    @test get(ini, "s", "next") == "1"

    # written as tab-indented continuation lines, and read back unchanged
    @test ini_string(ini) == """
        [s]
        key1 = first line
        \tsecond line
        \tthird line
        key2 = single
        key3 =
        \ta
        \tb
        key4 = paragraph one

        \tparagraph two
        key5 = with comments
        \tcontinued
        next = 1
        """
    @test contents(parse_ini(ini_string(ini))) == contents(ini)

    ini = Inifile()
    set(ini, "s", "k", "x\ny\n\nz")
    @test get(parse_ini(ini_string(ini)), "s", "k") == "x\ny\n\nz"

    # continuation of a default
    @test get(parse_ini("a = 1\n  2\n[s]\n"), "a") == "1\n2"

    # uniformly indented entries are separate entries, as in Python 3
    ini = parse_ini("""
        [s]
            a = 1
            b = 2
        [t]
          c = 3
        """)
    @test contents(ini) == ([], ["s" => ["a" => "1", "b" => "2"], "t" => ["c" => "3"]])

    # a section header cannot be continued
    @test_logs (:warn, r"line 2") parse_ini("[s]\n  stray\n")
end

@testset "inline comments" begin
    text = """
        [s]
        a = value ; comment
        b = value # comment
        c = no;comment
        d = no#comment
        e = ; only a comment
        url = http://example.com/#anchor
        f = multi ; one
            line # two
            ; full-line comment
        """
    ini = parse_ini(text)
    @test get(ini, "s", "a") == "value ; comment"
    @test get(ini, "s", "b") == "value # comment"
    @test get(ini, "s", "e") == "; only a comment"

    ini = parse_ini(text; inline_comment_prefixes=(";", "#"))
    @test get(ini, "s", "a") == "value"
    @test get(ini, "s", "b") == "value"
    @test get(ini, "s", "c") == "no;comment"
    @test get(ini, "s", "d") == "no#comment"
    @test get(ini, "s", "e") == ""
    @test get(ini, "s", "url") == "http://example.com/#anchor"
    @test get(ini, "s", "f") == "multi\nline"

    ini = parse_ini(text; inline_comment_prefixes=[';'])
    @test get(ini, "s", "a") == "value"
    @test get(ini, "s", "b") == "value # comment"

    ini = parse_ini("[s] ; comment\nk = v // note\n"; inline_comment_prefixes=(";", "//"))
    @test contents(ini) == ([], ["s" => ["k" => "v"]])

    @test_throws ArgumentError Inifile(inline_comment_prefixes=[""])
end

@testset "values are stored as strings" begin
    ini = Inifile()
    @test sections(ini) isa IniFile.OrderedDict{String,IniFile.OrderedDict{String,String}}
    @test defaults(ini) isa IniFile.OrderedDict{String,String}
    @test set(ini, SubString("s1", 1), SubString("k1", 1), SubString("v1", 1)) == "v1"
    @test only(keys(sections(ini))) isa String
    @test section(ini, "s1")["k1"] === "v1"
    set(ini, "s", "f", 1.5)
    set(ini, "s", "i", 42)
    set(ini, "s", "b", true)
    set(ini, "top", -1)
    @test collect(section(ini, "s")) == ["f" => "1.5", "i" => "42", "b" => "true"]
    @test get(ini, "top") == "-1"
    @test_throws MethodError set(ini, "s", "v", [1, 2])

    @test (@inferred Nothing get(ini, "s", "f")) == "1.5"
    @test (@inferred Nothing get(ini, "top")) == "-1"
    @test (@inferred get_float(ini, "s", "f")) === 1.5
    @test (@inferred get_int(ini, "s", "i")) === 42
    @test (@inferred get_bool(ini, "s", "b")) === true

    # setting nothing deletes, and does not create a section
    @test set(ini, "s", "i", nothing) === nothing
    @test !haskey(ini, "s", "i")
    @test set(ini, "nowhere", "k", nothing) === nothing
    @test !has_section(ini, "nowhere")
    @test set(ini, "top", nothing) === nothing
    @test get(ini, "top") === nothing
end

@testset "get_bool is strict" begin
    ini = parse_ini("""
        [b]
        t1 = 1
        t2 = yes
        t3 = TRUE
        t4 = On
        f1 = 0
        f2 = No
        f3 = false
        f4 = OFF
        typo = Ture
        number = 2
        empty =
        """)
    for k in ("t1", "t2", "t3", "t4")
        @test get_bool(ini, "b", k) === true
    end
    for k in ("f1", "f2", "f3", "f4")
        @test get_bool(ini, "b", k) === false
    end
    err = @test_throws ArgumentError get_bool(ini, "b", "typo")
    @test occursin("\"Ture\"", err.value.msg)
    @test occursin("\"typo\"", err.value.msg)
    @test occursin("\"b\"", err.value.msg)
    @test_throws ArgumentError get_bool(ini, "b", "number")
    @test_throws ArgumentError get_bool(ini, "b", "empty")
    # a default is only used for a missing key, not for a bad value
    @test_throws ArgumentError get_bool(ini, "b", "typo", false)
end

@testset "typed getters" begin
    ini = parse_ini("""
        fallback = 5
        [n]
        int = 42
        neg = -7
        float = 2.5
        exp = 1e3
        inf = Inf
        bad = abc
        half = 1.5
        """)
    @test get_int(ini, "n", "int") === 42
    @test get_int(ini, "n", "neg") === -7
    @test get_int(ini, "n", "fallback") === 5
    @test get_int(ini, "other", "fallback") === 5
    @test get_float(ini, "n", "float") === 2.5
    @test get_float(ini, "n", "int") === 42.0
    @test get_float(ini, "n", "exp") === 1000.0
    @test get_float(ini, "n", "inf") === Inf

    err = @test_throws ArgumentError get_int(ini, "n", "half")
    @test occursin("\"1.5\"", err.value.msg)
    @test occursin("\"half\"", err.value.msg)
    @test occursin("\"n\"", err.value.msg)
    @test_throws ArgumentError get_int(ini, "n", "bad")
    @test_throws ArgumentError get_float(ini, "n", "bad")
    @test_throws ArgumentError get_float(ini, "n", "bad", 0.0)

    # missing keys: a clear KeyError, or the default
    for f in (get_bool, get_int, get_float)
        err = @test_throws KeyError f(ini, "n", "missing")
        @test err.value == KeyError(("n", "missing"))
        @test_throws KeyError f(ini, "no section", "missing")
        @test f(ini, "n", "missing", nothing) === nothing
    end
    @test get_bool(ini, "n", "missing", true) === true
    @test get_int(ini, "n", "missing", 7) === 7
    @test get_float(ini, "n", "missing", 0.5) === 0.5
    @test get_int(ini, "n", "int", 7) === 42
end

@testset "haskey, has_section, section" begin
    ini = parse_ini("d = 0\n[s]\nk = v\n")
    @test haskey(ini, "s", "k")
    @test !haskey(ini, "s", "d")       # defaults are not considered
    @test !haskey(ini, "t", "k")
    @test has_section(ini, "s")
    @test section(ini, "s") === sections(ini)["s"]
    @test_throws KeyError section(ini, "t")
end

@testset "read" begin
    path = joinpath(mktempdir(), "x.ini")
    write(path, "[s]\nKey = v\n")

    ini = read(Inifile, path)
    @test ini isa Inifile
    @test get(ini, "s", "Key") == "v"
    @test get(read(Inifile, path; lowercase_keys=true), "s", "key") == "v"
    @test get(open(io -> read(Inifile, io), path), "s", "Key") == "v"
    @test read(Inifile(), path) isa Inifile

    # reading into a non-empty Inifile merges
    ini = Inifile()
    read(ini, IOBuffer("[s]\na = 1\n"))
    read(ini, IOBuffer("[s]\nb = 2\na = 3\n[t]\n"))
    @test contents(ini) == ([], ["s" => ["a" => "3", "b" => "2"], "t" => []])
end

@testset "show" begin
    ini = parse_ini("a = 1\n[s]\nb = 2\nc = 3\n")
    @test sprint(show, ini) == "Inifile(1 section, 3 keys)"
    @test repr(ini) == "Inifile(1 section, 3 keys)"
    @test sprint(show, [ini]) == "Inifile[Inifile(1 section, 3 keys)]"
    # print and string give the file contents, as in 0.5
    @test string(ini) == ini_string(ini) == "a = 1\n\n[s]\nb = 2\nc = 3\n"
    @test sprint(print, ini) == ini_string(ini)
    @test string(Inifile()) == ""
    @test repr("text/plain", ini) == "Inifile(1 section, 3 keys):\na = 1\n\n[s]\nb = 2\nc = 3"
    @test repr("text/plain", Inifile()) == "Inifile(0 sections, 0 keys)"
    @test sprint(show, parse_ini("[a]\nk = v\n[b]\n")) == "Inifile(2 sections, 1 key)"
end

@testset "issue #16: get(ini, key, default) is not ambiguous" begin
    ini = parse_ini("key = top\n[key]\nother = in section\n")
    @test get(ini, "key") == "top"
    @test get(ini, "key", "other") == "in section"   # always (section, key)
    @test get(ini, "missing") === nothing
    @test_throws MethodError get(ini, "key", 1.0)
    @test get(defaults(ini), "missing", 1.0) == 1.0
end

@testset "issue #20: update a key in an existing file" begin
    path = joinpath(mktempdir(), "app.ini")
    write(path, """
        [server]
        host = example.org
        port = 80

        [client]
        retries = 3
        """)
    ini = read(Inifile, path)
    set(ini, "server", "port", 8080)
    set(ini, "logging", "level", "debug")
    write(path, ini)
    @test read(path, String) == """
        [server]
        host = example.org
        port = 8080

        [client]
        retries = 3

        [logging]
        level = debug
        """
end

@testset "docstrings" begin
    meta = Base.Docs.meta(IniFile)
    for name in names(IniFile)
        @test haskey(meta, Base.Docs.Binding(IniFile, name))
    end
    for name in (:get, :haskey, :read, :write)
        @test haskey(meta, Base.Docs.Binding(Base, name))
    end
end

@testset "Aqua" begin
    Aqua.test_all(IniFile)
end

end
