source [file join [file dirname [file dirname [info script]]] http_common.tcl]

namespace eval ::plugins::http_put {}

proc ::plugins::http_put::execute {workspaceRoot arguments settings} {
    ::plugins::http_common::request \
        http_put PUT $arguments $settings required
}
