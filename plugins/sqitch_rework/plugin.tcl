source [file join \
    [file dirname [file dirname [info script]]] sqitch_common.tcl]

namespace eval ::plugins::sqitch_rework {}

proc ::plugins::sqitch_rework::execute {
    workspaceRoot arguments settings
} {
    set change [::plugins::sqitch_common::changeName \
        [dict get $arguments change] "sqitch_rework change"]
    set note [::plugins::sqitch_common::note \
        [dict get $arguments note] "sqitch_rework note"]
    ::plugins::sqitch_common::run $settings \
        [list rework --change $change --note $note --no-all --no-edit]
}
