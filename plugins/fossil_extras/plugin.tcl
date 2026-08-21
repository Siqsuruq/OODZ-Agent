source [file join [file dirname [file dirname [info script]]] fossil_common.tcl]

namespace eval ::plugins::fossil_extras {}

proc ::plugins::fossil_extras::execute {
    workspaceRoot arguments settings
} {
    ::plugins::fossil_common::run $settings \
        [list extras --rel-paths]
}
