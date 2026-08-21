source [file join [file dirname [file dirname [info script]]] fossil_common.tcl]

namespace eval ::plugins::fossil_timeline {}

proc ::plugins::fossil_timeline::execute {
    workspaceRoot arguments settings
} {
    set defaultLimit 20
    if {[dict exists $settings default_limit]} {
        set defaultLimit [::plugins::fossil_common::positiveInteger \
            [dict get $settings default_limit] \
            "fossil_timeline default_limit setting"]
    }
    set maximumLimit 100
    if {[dict exists $settings maximum_limit]} {
        set maximumLimit [::plugins::fossil_common::positiveInteger \
            [dict get $settings maximum_limit] \
            "fossil_timeline maximum_limit setting"]
    }
    set limit $defaultLimit
    if {[dict exists $arguments limit]} {
        set limit [::plugins::fossil_common::positiveInteger \
            [dict get $arguments limit] "fossil_timeline limit"]
    }
    if {$limit > $maximumLimit} {
        error "fossil_timeline limit exceeds configured maximum: $maximumLimit"
    }
    ::plugins::fossil_common::run $settings \
        [list timeline -t ci -n $limit --oneline -q]
}
