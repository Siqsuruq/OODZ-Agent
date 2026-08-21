source [file join [file dirname [file dirname [info script]]] fossil_common.tcl]

namespace eval ::plugins::fossil_merge {}

proc ::plugins::fossil_merge::execute {
    workspaceRoot arguments settings
} {
    set maximum 200
    if {[dict exists $settings max_source_chars]} {
        set maximum [::plugins::fossil_common::positiveInteger \
            [dict get $settings max_source_chars] \
            "fossil_merge max_source_chars setting"]
    }
    set source [dict get $arguments source]
    if {[string trim $source] eq ""} {
        error "fossil_merge source must not be empty"
    }
    if {[string length $source] > $maximum} {
        error "fossil_merge source exceeds configured limit: $maximum"
    }
    if {[string first "\x00" $source] >= 0} {
        error "fossil_merge source contains a null character"
    }
    ::plugins::fossil_common::run $settings \
        [list merge --nosync -- $source]
}
