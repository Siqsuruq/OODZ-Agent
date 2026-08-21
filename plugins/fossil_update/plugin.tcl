source [file join [file dirname [file dirname [info script]]] fossil_common.tcl]

namespace eval ::plugins::fossil_update {}

proc ::plugins::fossil_update::execute {
    workspaceRoot arguments settings
} {
    ::plugins::fossil_common::run $settings [list update --nosync]
}
