source [file join [file dirname [file dirname [info script]]] fossil_common.tcl]

namespace eval ::plugins::fossil_add {}

proc ::plugins::fossil_add::execute {
    workspaceRoot arguments settings
} {
    set path [::plugins::fossil_common::path fossil_add $workspaceRoot $arguments true]
    ::plugins::fossil_common::run $settings [list add -- $path]
}
