source [file join [file dirname [file dirname [info script]]] fossil_common.tcl]

namespace eval ::plugins::fossil_status {}

proc ::plugins::fossil_status::execute {
    workspaceRoot arguments settings
} {
    ::plugins::fossil_common::run $settings [list status]
}
