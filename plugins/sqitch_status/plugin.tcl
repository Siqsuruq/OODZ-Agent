source [file join \
    [file dirname [file dirname [info script]]] sqitch_common.tcl]

namespace eval ::plugins::sqitch_status {}

proc ::plugins::sqitch_status::execute {
    workspaceRoot arguments settings
} {
    ::plugins::sqitch_common::run $settings [list status]
}
