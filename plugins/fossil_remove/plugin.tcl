source [file join [file dirname [file dirname [info script]]] fossil_common.tcl]

namespace eval ::plugins::fossil_remove {}

proc ::plugins::fossil_remove::execute {
    workspaceRoot arguments settings
} {
    set path [::plugins::fossil_common::path \
        fossil_remove $workspaceRoot $arguments true]
    ::plugins::fossil_common::run $settings [list rm --hard -- $path]
}
