source [file join [file dirname [file dirname [info script]]] http_common.tcl]

namespace eval ::plugins::http_post {}

proc ::plugins::http_post::buildUrl {arguments settings} {
    ::plugins::http_common::buildUrl http_post $arguments $settings
}

proc ::plugins::http_post::validateJson {jsonBody} {
    ::plugins::http_common::validateJson http_post $jsonBody
}

proc ::plugins::http_post::tlsOptions {settings} {
    ::plugins::http_common::tlsOptions http_post $settings
}

proc ::plugins::http_post::execute {workspaceRoot arguments settings} {
    ::plugins::http_common::request \
        http_post POST $arguments $settings required
}
