source [file join [file dirname [file dirname [info script]]] database_common.tcl]
namespace eval ::plugins::database_describe {}
proc ::plugins::database_describe::execute {workspaceRoot arguments settings} {
    set table [string trim [dict get $arguments table]]
    if {$table eq ""} {error "Table name must not be empty"}
    set configuration [::plugins::database_common::settings $workspaceRoot $settings]
    lassign [::plugins::database_common::open $configuration [dict getdef $arguments profile ""] false] profile db
    try {
        return [dict create profile $profile table $table columns [$db columns $table] primary_keys [$db primarykeys $table] foreign_keys [$db foreignkeys -foreign $table]]
    } finally {$db close}
}
