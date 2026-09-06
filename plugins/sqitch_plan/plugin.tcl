source [file join \
    [file dirname [file dirname [info script]]] sqitch_common.tcl]

namespace eval ::plugins::sqitch_plan {}

proc ::plugins::sqitch_plan::execute {
    workspaceRoot arguments settings
} {
    set defaultLimit 100
    if {[dict exists $settings default_limit]} {
        set defaultLimit [::plugins::sqitch_common::boundedInteger \
            [dict get $settings default_limit] \
            "sqitch_plan default_limit setting" 1 500]
    }
    set maximumLimit 500
    if {[dict exists $settings maximum_limit]} {
        set maximumLimit [::plugins::sqitch_common::boundedInteger \
            [dict get $settings maximum_limit] \
            "sqitch_plan maximum_limit setting" 1 500]
    }
    if {$defaultLimit > $maximumLimit} {
        error "sqitch_plan default_limit exceeds configured maximum: $maximumLimit"
    }

    set limit $defaultLimit
    if {[dict exists $arguments limit]} {
        set limit [::plugins::sqitch_common::boundedInteger \
            [dict get $arguments limit] "sqitch_plan limit" 1 500]
    }
    if {$limit > $maximumLimit} {
        error "sqitch_plan limit exceeds configured maximum: $maximumLimit"
    }

    ::plugins::sqitch_common::run $settings \
        [list plan --max-count $limit --oneline --no-color --no-headers]
}
