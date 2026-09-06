source [file join \
    [file dirname [file dirname [info script]]] sqitch_common.tcl]

namespace eval ::plugins::sqitch_deploy {}

proc ::plugins::sqitch_deploy::execute {
    workspaceRoot arguments settings
} {
    ::plugins::sqitch_common::run $settings [list deploy]
}
