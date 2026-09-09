namespace eval ::plugins::read_file {}

proc ::plugins::read_file::execute {workspaceRoot arguments settings} {
    set ranged [expr {[dict exists $arguments start_line]
        || [dict exists $arguments end_line]}]
    set startLine 1
    if {[dict exists $arguments start_line]} {
        set startLine [dict get $arguments start_line]
    }
    if {![string is entier -strict $startLine] || $startLine < 1} {
        error "start_line must be a positive integer"
    }
    set endLine [expr {$startLine + 199}]
    if {[dict exists $arguments end_line]} {
        set endLine [dict get $arguments end_line]
    }
    if {![string is entier -strict $endLine] || $endLine < $startLine} {
        error "end_line must be an integer greater than or equal to start_line"
    }
    set truncated [expr {$endLine - $startLine + 1 > 200}]
    if {$truncated} {
        set endLine [expr {$startLine + 199}]
    }

    set path [::PluginSupport::resolveWorkspacePath \
        $workspaceRoot [dict get $arguments path]]
    if {![file isfile $path]} {
        error "File does not exist: [dict get $arguments path]"
    }

    set channel [open $path r]
    try {
        fconfigure $channel -encoding utf-8
        set content [read $channel]
    } finally {
        close $channel
    }
    if {!$ranged} {
        return $content
    }
    if {$content eq ""} {
        error "Cannot read a line range from an empty file: [dict get $arguments path]"
    }
    set lines [split $content "\n"]
    if {$startLine > [llength $lines]} {
        error "start_line exceeds file length: [dict get $arguments path]"
    }
    set endLine [expr {min($endLine, [llength $lines])}]
    set output {}
    for {set lineNumber $startLine} {$lineNumber <= $endLine} \
            {incr lineNumber} {
        set line [string trimright \
            [lindex $lines [expr {$lineNumber - 1}]] "\r"]
        lappend output "$lineNumber: $line"
    }
    if {$truncated} {
        return "Requested range truncated to lines $startLine-$endLine.\n[join $output \n]"
    }
    return [join $output "\n"]
}
