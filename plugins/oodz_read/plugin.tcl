namespace eval ::plugins::oodz_read {}

proc ::plugins::oodz_read::execute {workspaceRoot arguments settings} {
    set relativePath [string trim [dict get $arguments path]]
    if {$relativePath eq ""} {
        error "OODZ file path must not be empty"
    }
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
    if {$endLine - $startLine + 1 > 200} {
        error "OODZ reads are limited to 200 lines"
    }

    set path [::PluginSupport::resolveReferencePath oodz $relativePath]
    if {![file isfile $path]} {
        error "OODZ file does not exist: $relativePath"
    }
    if {[file size $path] > 1048576} {
        error "OODZ file exceeds 1 MiB: $relativePath"
    }
    set channel [open $path rb]
    try {
        set bytes [read $channel]
    } finally {
        close $channel
    }
    if {[string first \x00 $bytes] >= 0} {
        error "OODZ file appears to be binary: $relativePath"
    }
    if {[catch {encoding convertfrom utf-8 $bytes} content]} {
        error "OODZ file is not valid UTF-8: $relativePath"
    }
    if {$content eq ""} {
        return "OODZ file is empty: $relativePath"
    }
    set lines [split $content "\n"]
    if {$startLine > [llength $lines]} {
        error "start_line exceeds file length: $relativePath"
    }
    set endLine [expr {min($endLine, [llength $lines])}]
    set output {}
    for {set lineNumber $startLine} {$lineNumber <= $endLine} \
            {incr lineNumber} {
        set line [string trimright [lindex $lines [expr {$lineNumber - 1}]] "\r"]
        lappend output "$lineNumber: $line"
    }
    return [join $output "\n"]
}
