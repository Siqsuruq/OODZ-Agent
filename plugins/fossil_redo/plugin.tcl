source [file join [file dirname [file dirname [info script]]] fossil_common.tcl]

namespace eval ::plugins::fossil_redo {}

proc ::plugins::fossil_redo::execute {
    workspaceRoot arguments settings
} {
    set path [::plugins::fossil_common::path \
        fossil_redo $workspaceRoot $arguments]
    ::plugins::fossil_common::run $settings [list redo -- $path]
}
