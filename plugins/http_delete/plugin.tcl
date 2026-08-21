source [file join [file dirname [file dirname [info script]]] http_common.tcl]

namespace eval ::plugins::http_delete {}

proc ::plugins::http_delete::execute {workspaceRoot arguments settings} {
    ::plugins::http_common::request \
        http_delete DELETE $arguments $settings optional
}
