source [file join [file dirname [file dirname [info script]]] fossil_common.tcl]

namespace eval ::plugins::fossil_undo {}

proc ::plugins::fossil_undo::execute {
    workspaceRoot arguments settings
} {
    set path [::plugins::fossil_common::path \
        fossil_undo $workspaceRoot $arguments]
    ::plugins::fossil_common::run $settings [list undo -- $path]
}
