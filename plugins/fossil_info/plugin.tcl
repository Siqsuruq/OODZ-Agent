source [file join [file dirname [file dirname [info script]]] fossil_common.tcl]

namespace eval ::plugins::fossil_info {}

proc ::plugins::fossil_info::execute {
    workspaceRoot arguments settings
} {
    ::plugins::fossil_common::run $settings [list info]
}
