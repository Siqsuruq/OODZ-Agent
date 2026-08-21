source [file join [file dirname [file dirname [info script]]] fossil_common.tcl]

namespace eval ::plugins::fossil_stash_list {}

proc ::plugins::fossil_stash_list::execute {
    workspaceRoot arguments settings
} {
    ::plugins::fossil_common::run $settings [list stash list --verbose]
}
