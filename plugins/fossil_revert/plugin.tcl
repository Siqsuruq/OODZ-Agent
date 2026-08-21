source [file join [file dirname [file dirname [info script]]] fossil_common.tcl]

namespace eval ::plugins::fossil_revert {}

proc ::plugins::fossil_revert::execute {
    workspaceRoot arguments settings
} {
    set path [::plugins::fossil_common::path \
        fossil_revert $workspaceRoot $arguments true]
    ::plugins::fossil_common::run $settings [list revert -- $path]
}
