source [file join [file dirname [file dirname [info script]]] database_common.tcl]
namespace eval ::plugins::database_tables {}
proc ::plugins::database_tables::execute {workspaceRoot arguments settings} {
    set configuration [::plugins::database_common::settings $workspaceRoot $settings]
    lassign [::plugins::database_common::open $configuration [dict getdef $arguments profile ""] false] profile db
    try {
        set pattern [dict getdef $arguments pattern "%"]
        return [dict create profile $profile tables [$db tables $pattern]]
    } finally {$db close}
}
