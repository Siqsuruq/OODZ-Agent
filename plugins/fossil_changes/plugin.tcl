source [file join [file dirname [file dirname [info script]]] fossil_common.tcl]

namespace eval ::plugins::fossil_changes {}

proc ::plugins::fossil_changes::execute {
    workspaceRoot arguments settings
} {
    ::plugins::fossil_common::run $settings \
        [list changes --classify --no-merge --rel-paths --verbose]
}
