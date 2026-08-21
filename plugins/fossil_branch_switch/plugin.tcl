source [file join [file dirname [file dirname [info script]]] fossil_common.tcl]

namespace eval ::plugins::fossil_branch_switch {}

proc ::plugins::fossil_branch_switch::execute {
    workspaceRoot arguments settings
} {
    set maximum 200
    if {[dict exists $settings max_name_chars]} {
        set maximum [::plugins::fossil_common::positiveInteger \
            [dict get $settings max_name_chars] \
            "fossil_branch_switch max_name_chars setting"]
    }
    set name [dict get $arguments name]
    if {[string trim $name] eq ""} {
        error "fossil_branch_switch name must not be empty"
    }
    if {[string length $name] > $maximum} {
        error "fossil_branch_switch name exceeds configured limit: $maximum"
    }
    if {[string first "\x00" $name] >= 0} {
        error "fossil_branch_switch name contains a null character"
    }
    ::plugins::fossil_common::run $settings \
        [list update --nosync -- $name]
}
