#!/usr/bin/env tclsh

package require Tcl 9.0
package require tcltest 2.5

namespace import ::tcltest::*

if {[llength $::argv] > 0} {
    ::tcltest::configure {*}$::argv
}

set testsDir [file dirname [file normalize [info script]]]
set ownedTestTemporaryDirectory ""
if {[lsearch -exact $::argv -tmpdir] < 0} {
    set ownedTestTemporaryDirectory [file tempdir oodz-agent-tests]
    ::tcltest::configure -tmpdir $ownedTestTemporaryDirectory
}

::tcltest::configure -testdir $testsDir
if {[lsearch -exact $::argv -file] < 0} {
    ::tcltest::configure -file *.test
}
set failed [::tcltest::runAllTests]

if {$ownedTestTemporaryDirectory ne ""
        && [file exists $ownedTestTemporaryDirectory]} {
    file delete -force $ownedTestTemporaryDirectory
}

if {$failed} {
    exit 1
}
