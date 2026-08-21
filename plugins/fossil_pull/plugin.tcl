source [file join [file dirname [file dirname [info script]]] fossil_common.tcl]

namespace eval ::plugins::fossil_pull {}

proc ::plugins::fossil_pull::execute {
    workspaceRoot arguments settings
} {
    ::plugins::fossil_common::run $settings [list pull]
}
