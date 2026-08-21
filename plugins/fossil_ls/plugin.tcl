source [file join [file dirname [file dirname [info script]]] fossil_common.tcl]

namespace eval ::plugins::fossil_ls {}

proc ::plugins::fossil_ls::execute {
    workspaceRoot arguments settings
} {
    ::plugins::fossil_common::run $settings [list ls --verbose]
}
