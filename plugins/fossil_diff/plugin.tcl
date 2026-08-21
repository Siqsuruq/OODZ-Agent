source [file join [file dirname [file dirname [info script]]] fossil_common.tcl]

namespace eval ::plugins::fossil_diff {}

proc ::plugins::fossil_diff::execute {
    workspaceRoot arguments settings
} {
    set commandArguments [list diff -i]
    if {[dict exists $arguments path]} {
        set path [::plugins::fossil_common::path \
            fossil_diff $workspaceRoot $arguments]
        lappend commandArguments -- $path
    }
    ::plugins::fossil_common::run $settings $commandArguments
}
