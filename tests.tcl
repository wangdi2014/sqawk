#!/usr/bin/env tclsh
# Sqawk, an SQL Awk.
# Copyright (C) 2015 Danyil Bohdan
# License: MIT

package require tcltest
package require fileutil

namespace eval ::sqawk::tests {
    variable path [file dirname [file dirname [file normalize $argv0/___]]]
    variable setup [list apply {{path} {
        cd $path
    }} $path]

    # Create and open temporary files (read/write), run a script then close and delete the
    # files. $args is a list of the format {fnVarName1 chVarName1 fnVarName2
    # chVarName2 ... script}.
    proc with-temp-files args {
        set files {}
        set channels {}

        set script [lindex $args end]
        foreach {fnVarName chVarName} [lrange $args 0 end-1] {
            set filename [::fileutil::tempfile]
            uplevel 1 [list set $fnVarName $filename]
            set upvars_$fnVarName filename
            if {$chVarName ne ""} {
                set channel [open $filename w+]
                uplevel 1 [list set $chVarName $channel]
                lappend channels $channel
            }
        }

        uplevel 1 $script

        foreach channel $channels {
            catch { close $channel }
        }
        foreach filename $files {
            file delete $filename
        }
    }

    tcltest::test test1 {Handle broken pipe} \
            -constraints unix \
            -setup $setup \
            -body {
        with-temp-files filename ch {
            puts $ch "line 1\nline 2\nline 3"
            close $ch
            set result [exec \
                    tclsh sqawk.tcl {select a0 from a} $filename | head -n 1]
        }
        return $result
    } -result {line 1}

    tcltest::test test2 {Fail on bad query or missing file} \
            -setup $setup \
            -body {
        set result {}
        # Bad query.
        lappend result [catch {
            exec tclsh sqawk.tcl -1 asdf sqawk.tcl
        }]
        # Missing file.
        lappend result [catch {
            exec tclsh sqawk.tcl -1 {select a0 from a} missing-file
        }]
        return $result
    } -result {1 1}

    tcltest::test test3 {JOIN on two files from examples/hp/} \
            -constraints unix \
            -setup $setup \
            -body {
        with-temp-files filename {
            exec tclsh sqawk.tcl {
                select a1, b1, a2 from a inner join b on a2 = b2
                where b1 < 10000 order by b1
            } examples/hp/MD5SUMS examples/hp/du-bytes > $filename

            set result [exec diff examples/hp/results.correct $filename]
        }
        return $result
    } -result {}

    tcltest::test test4 {JOIN on files from examples/three-files/, FS setting} \
            -constraints unix \
            -setup $setup \
            -body {
        with-temp-files filename {
            set dir examples/three-files/
            exec tclsh sqawk.tcl -FS , {
                select a1, a2, b2, c2 from a inner join b on a1 = b1
                inner join c on a1 = c1
            } $dir/1 FS=_ FS=, $dir/2 $dir/3 > $filename
            unset dir
            set result \
                    [exec diff examples/three-files/results.correct $filename]
        }
        return $result
    } -result {}

    tcltest::test test5 {Custom table names} \
            -setup $setup \
            -body {
        with-temp-files filename1 ch1 {
            with-temp-files filename2 ch2 {
                puts $ch1 "foo 1\nfoo 2\nfoo 3"
                puts $ch2 "bar 4\nbar 5\nbar 6"
                close $ch1
                close $ch2
                set result [exec tclsh sqawk.tcl {
                    select foo2 from foo; select b2 from b
                } table=foo $filename1 $filename2]
            }
        }
        return $result
    } -result "1\n2\n3\n4\n5\n6"

    tcltest::test test6 {Custom table names and prefixes} \
            -setup $setup \
            -body {
        with-temp-files filename1 ch1 filename2 ch2 {
            puts $ch1 "foo 1\nfoo 2\nfoo 3"
            puts $ch2 "bar 4\nbar 5\nbar 6"
            close $ch1
            close $ch2
            set result [exec tclsh sqawk.tcl {
                select foo.x2 from foo; select baz2 from bar
            } table=foo prefix=x $filename1 table=bar prefix=baz $filename2]
        }
        return $result
    } -result "1\n2\n3\n4\n5\n6"

    tcltest::test test7 {Header row} \
            -setup $setup \
            -body {
        with-temp-files filename ch {
            puts $ch "name\tposition\toffice\tphone"
            puts $ch "Smith\tCEO\t10\t555-1234"
            puts $ch "James\tHead of marketing\t11\t555-1235"
            puts $ch "McDonald\tDeveloper\t12\t555-1236\tGood at tables"
            close $ch
            set result [exec tclsh sqawk.tcl {
                select name, office from staff
                where position = "CEO"
                        or staff.phone = "555-1234"
                        or staff.a5 = "Good at tables"
            } FS=\t table=staff prefix=a header=1 $filename]
        }
        return $result
    } -result "Smith 10\nMcDonald 12"

    # Exit with a nonzero status if there are failed tests.
    if {$::tcltest::numTests(Failed) > 0} {
        exit 1
    }
}
