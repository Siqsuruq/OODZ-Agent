source [file join \
    [file dirname [file dirname [info script]]] sqitch_common.tcl]

namespace eval ::plugins::sqitch_tag {}

proc ::plugins::sqitch_tag::execute {
    workspaceRoot arguments settings
} {
    set tag [::plugins::sqitch_common::changeName \
        [dict get $arguments tag] "sqitch_tag tag"]
    set change [::plugins::sqitch_common::objectIdentifier \
        [dict get $arguments change] "sqitch_tag change"]
    set note [::plugins::sqitch_common::note \
        [dict get $arguments note] "sqitch_tag note"]
    ::plugins::sqitch_common::run $settings \
        [list tag --tag $tag --change $change --note $note --no-all]
}
