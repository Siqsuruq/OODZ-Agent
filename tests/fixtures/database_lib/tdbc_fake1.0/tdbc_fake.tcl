namespace eval ::tdbc::fake {}

::oo::class create ::tdbc::fake::connection {
    constructor {args} {}
    method close {} {my destroy}
    method tables {pattern} {return [dict create people [dict create type table]]}
    method columns {table args} {return [dict create id [dict create type integer nullable 0] name [dict create type varchar nullable 1]]}
    method primarykeys {table} {return [list [dict create tableName $table columnName id ordinalPosition 1]]}
    method foreignkeys {args} {return [list [dict create foreignTable people foreignColumn manager_id primaryTable people primaryColumn id]]}
    method foreach {args} {
        set marker [lsearch -exact $args --]
        set variable [lindex $args [expr {$marker + 1}]]
        set script [lindex $args end]
        foreach row [list [dict create id 1 name Ada] [dict create id 2 name Linus] [dict create id 3 name Grace]] {
            uplevel 1 [list set $variable $row]
            set code [catch {uplevel 1 $script} result options]
            if {$code == 3} {break}
            if {$code != 0} {return -options $options $result}
        }
    }
    method allrows {args} {return [list [dict create id 9 status written]]}
}

package provide tdbc::fake 1.0
