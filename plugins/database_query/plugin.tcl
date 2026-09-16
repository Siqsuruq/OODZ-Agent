source [file join [file dirname [file dirname [info script]]] database_common.tcl]
namespace eval ::plugins::database_query {}
proc ::plugins::database_query::execute {workspaceRoot arguments settings} {
    set sql [string trim [dict get $arguments sql]]
    if {$sql eq ""} {error "SQL query must not be empty"}
    set configuration [::plugins::database_common::settings $workspaceRoot $settings]
    set limit [::plugins::database_common::limits $configuration $arguments]
    lassign [::plugins::database_common::open $configuration [dict getdef $arguments profile ""] false] profile db
    set rows {}
    set truncated false
    try {
        $db foreach -as dicts -- row $sql [dict getdef $arguments parameters {}] {
            if {[llength $rows] >= $limit} {set truncated true; break}
            lappend rows $row
        }
        return [dict merge [dict create profile $profile] [::plugins::database_common::formatRows $configuration $rows $truncated]]
    } finally {$db close}
}
