source [file join \
    [file dirname [file dirname [info script]]] sqitch_common.tcl]

namespace eval ::plugins::sqitch_revert {}

proc ::plugins::sqitch_revert::execute {
    workspaceRoot arguments settings
} {
    set destination [::plugins::sqitch_common::objectIdentifier \
        [dict get $arguments to] "sqitch_revert destination"]
    ::plugins::sqitch_common::run $settings \
        [list revert --to-change $destination -y]
}
