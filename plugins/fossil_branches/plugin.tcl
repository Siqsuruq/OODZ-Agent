source [file join [file dirname [file dirname [info script]]] fossil_common.tcl]

namespace eval ::plugins::fossil_branches {}

proc ::plugins::fossil_branches::execute {
    workspaceRoot arguments settings
} {
    ::plugins::fossil_common::run $settings [list branch list --all]
}
