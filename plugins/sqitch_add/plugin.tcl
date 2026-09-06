source [file join \
    [file dirname [file dirname [info script]]] sqitch_common.tcl]

namespace eval ::plugins::sqitch_add {}

proc ::plugins::sqitch_add::execute {
    workspaceRoot arguments settings
} {
    set change [::plugins::sqitch_common::changeName \
        [dict get $arguments change] "sqitch_add change"]
    set note [::plugins::sqitch_common::note \
        [dict get $arguments note] "sqitch_add note"]

    ::plugins::sqitch_common::run $settings \
        [list add --change $change --note $note --no-all --no-edit]
}
