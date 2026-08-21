source [file join [file dirname [file dirname [info script]]] fossil_common.tcl]

namespace eval ::plugins::fossil_push {}

proc ::plugins::fossil_push::execute {
    workspaceRoot arguments settings
} {
    ::plugins::fossil_common::run $settings [list push]
}
