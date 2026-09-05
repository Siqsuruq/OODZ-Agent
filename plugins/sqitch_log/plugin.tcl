source [file join \
    [file dirname [file dirname [info script]]] sqitch_common.tcl]

namespace eval ::plugins::sqitch_log {}

proc ::plugins::sqitch_log::execute {
    workspaceRoot arguments settings
} {
    set limit 20
    if {[dict exists $arguments limit]} {
        set limit [dict get $arguments limit]
    }
    set limit [::plugins::sqitch_common::boundedInteger \
        $limit "sqitch_log limit" 1 100]
    ::plugins::sqitch_common::run $settings \
        [list log --max-count $limit --oneline --no-color]
}
