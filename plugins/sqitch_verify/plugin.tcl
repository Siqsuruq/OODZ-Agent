source [file join \
    [file dirname [file dirname [info script]]] sqitch_common.tcl]

namespace eval ::plugins::sqitch_verify {}

proc ::plugins::sqitch_verify::execute {
    workspaceRoot arguments settings
} {
    ::plugins::sqitch_common::run $settings [list verify]
}
