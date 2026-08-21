source [file join [file dirname [file dirname [info script]]] http_common.tcl]

namespace eval ::plugins::http_get {}

proc ::plugins::http_get::buildUrl {arguments settings} {
    ::plugins::http_common::buildUrl http_get $arguments $settings
}

proc ::plugins::http_get::tlsOptions {settings} {
    ::plugins::http_common::tlsOptions http_get $settings
}

proc ::plugins::http_get::execute {workspaceRoot arguments settings} {
    ::plugins::http_common::request \
        http_get GET $arguments $settings none
}
