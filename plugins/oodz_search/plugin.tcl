namespace eval ::plugins::oodz_search {}

proc ::plugins::oodz_search::relativePath {root path} {
    if {$path eq $root} {
        return "."
    }
    return [string range $path [expr {[string length $root] + 1}] end]
}

proc ::plugins::oodz_search::execute {workspaceRoot arguments settings} {
    set query [string trim [dict get $arguments query]]
    if {$query eq ""} {
        error "OODZ search query must not be empty"
    }
    set relativePath "."
    if {[dict exists $arguments path]} {
        set relativePath [string trim [dict get $arguments path]]
        if {$relativePath eq ""} {
            error "OODZ search path must not be empty"
        }
    }
    set startPath [::PluginSupport::resolveReferencePath oodz $relativePath]
    if {![file exists $startPath]} {
        error "OODZ search path does not exist: $relativePath"
    }
    set referenceRoot [::PluginSupport::resolveReferencePath oodz .]
    set pending [list $startPath]
    set matches {}
    set maximumMatches 100
    set loweredQuery [string tolower $query]

    while {[llength $pending] > 0 \
            && [llength $matches] < $maximumMatches} {
        set path [lindex $pending end]
        set pending [lrange $pending 0 end-1]
        if {![::PluginSupport::isWithin $path $referenceRoot]} {
            continue
        }
        if {[file isdirectory $path]} {
            if {[file tail $path] in {.git tmp}} {
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
        if {![file isfile $path] || ![file readable $path] \
                || [file size $path] > 1048576} {
            continue
        }
        if {[catch {
            set channel [open $path rb]
            try {
                set bytes [read $channel]
            } finally {
                close $channel
            }
            if {[string first \x00 $bytes] >= 0} {
                continue
            }
            set content [encoding convertfrom utf-8 $bytes]
        }]} {
            continue
        }
        set lineNumber 0
        foreach line [split $content "\n"] {
            incr lineNumber
            set line [string trimright $line "\r"]
            if {[string first $loweredQuery [string tolower $line]] >= 0} {
                set preview [string range [string trim $line] 0 299]
                lappend matches "[relativePath \
                    $referenceRoot $path]:$lineNumber: $preview"
                if {[llength $matches] >= $maximumMatches} {
                    break
                }
            }
        }
    }
    if {[llength $matches] == 0} {
        return "No OODZ matches found."
    }
    return [join $matches "\n"]
}
