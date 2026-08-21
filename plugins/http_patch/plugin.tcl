source [file join [file dirname [file dirname [info script]]] http_common.tcl]

namespace eval ::plugins::http_patch {}

proc ::plugins::http_patch::execute {workspaceRoot arguments settings} {
    ::plugins::http_common::request \
        http_patch PATCH $arguments $settings required
}
