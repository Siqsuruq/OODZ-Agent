namespace eval ::plugins::search_text {}

proc ::plugins::search_text::relativePath {workspaceRoot path} {
    if {$path eq $workspaceRoot} {
        return "."
    }
    return [string range $path \
        [expr {[string length $workspaceRoot] + 1}] end]
}

proc ::plugins::search_text::execute {workspaceRoot arguments settings} {
    set query [dict get $arguments query]
    if {$query eq ""} {
        error "Search query must not be empty"
    }

    set relativePath "."
    if {[dict exists $arguments path]} {
        set relativePath [dict get $arguments path]
    }
    set startPath [::PluginSupport::resolveWorkspacePath \
        $workspaceRoot $relativePath]
    if {![file exists $startPath]} {
        error "Search path does not exist: $relativePath"
    }

    set pending [list $startPath]
    set matches {}
    set maximumMatches 100
    set loweredQuery [string tolower $query]

    while {[llength $pending] > 0
            && [llength $matches] < $maximumMatches} {
        set path [lindex $pending end]
        set pending [lrange $pending 0 end-1]

        if {![::PluginSupport::isWithin $path $workspaceRoot]} {
            continue
        }
        if {[file isdirectory $path]} {
            if {[file tail $path] eq ".git"} {
                continue
            }
            foreach child [concat \
                    [glob -nocomplain -directory $path *] \
                    [glob -nocomplain -directory $path .*]] {
                if {[file tail $child] ni {. ..}} {
                    lappend pending $child
                }
            }
            continue
        }
        if {![file isfile $path] || [file size $path] > 1048576} {
            continue
        }

        if {[catch {
            set channel [open $path r]
            try {
                fconfigure $channel -encoding utf-8
                set lineNumber 0
                while {[gets $channel line] >= 0} {
                    incr lineNumber
                    if {[string first $loweredQuery \
                            [string tolower $line]] >= 0} {
                        set preview [string range [string trim $line] 0 299]
                        lappend matches "[::plugins::search_text::relativePath \
                            $workspaceRoot $path]:$lineNumber: $preview"
                        if {[llength $matches] >= $maximumMatches} {
                            break
                        }
                    }
                }
            } finally {
                close $channel
            }
        }]} {
            continue
        }
    }

    if {[llength $matches] == 0} {
        return "No matches found."
    }
    return [join $matches "\n"]
}
