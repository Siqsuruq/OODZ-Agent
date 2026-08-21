namespace eval ::plugins::oodz_lookup {
    variable indexPath [file join [file dirname [info script]] FRAMEWORK_INDEX.json]
}

proc ::plugins::oodz_lookup::execute {workspaceRoot arguments settings} {
    variable indexPath
    package require json
    set originalQuery [string trim [dict get $arguments query]]
    set query [string tolower $originalQuery]
    if {$query eq ""} {
        error "OODZ lookup query must not be empty"
    }
    if {![file isfile $indexPath]} {
        error "OODZ framework index is missing"
    }
    set channel [open $indexPath rb]
    try {
        set bytes [read $channel]
    } finally {
        close $channel
    }
    if {[catch {encoding convertfrom utf-8 $bytes} document]} {
        error "OODZ framework index is not valid UTF-8"
    }
    if {[catch {::json::json2dict $document} index]} {
        error "OODZ framework index is not valid JSON"
    }

    set matches {}
    foreach component [dict get $index components] {
        set searchable [string tolower [join [list \
            [dict get $component name] [dict get $component category] \
            [dict get $component summary] \
            [join [dict get $component keywords] " "] \
            [dict get $component source]] " "]]
        if {[string first $query $searchable] >= 0} {
            lappend matches $component
        }
    }
    if {[llength $matches] == 0} {
        return "No OODZ components found for: $originalQuery"
    }
    set output {}
    foreach component [lrange $matches 0 19] {
        lappend output [join [list \
            "Name: [dict get $component name]" \
            "Category: [dict get $component category]" \
            "Summary: [dict get $component summary]" \
            "Source: [dict get $component source]" \
            "Keywords: [join [dict get $component keywords] {, }]" \
        ] "\n"]
    }
    return [join $output "\n\n"]
}
