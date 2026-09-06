source [file join \
    [file dirname [file dirname [info script]]] sqitch_common.tcl]

namespace eval ::plugins::sqitch_show {}

proc ::plugins::sqitch_show::execute {
    workspaceRoot arguments settings
} {
    set object [::plugins::sqitch_common::objectIdentifier \
        [dict get $arguments object] "sqitch_show object"]

    set view change
    if {[dict exists $arguments view]} {
        set view [string tolower [string trim [dict get $arguments view]]]
    }
    if {$view ni {change tag deploy revert verify}} {
        error "sqitch_show view must be one of: change, tag, deploy, revert, verify"
    }

    ::plugins::sqitch_common::run $settings [list show $view $object]
}
