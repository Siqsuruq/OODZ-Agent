namespace eval ::plugins::find_files {}

proc ::plugins::find_files::relativePath {workspaceRoot path} {
    return [string range $path \
        [expr {[string length $workspaceRoot] + 1}] end]
}

proc ::plugins::find_files::execute {workspaceRoot arguments settings} {
    set pattern [dict get $arguments pattern]
    if {$pattern eq ""} {
        error "Filename pattern must not be empty"
    }
    if {[string first "/" $pattern] >= 0
            || [string first "\\" $pattern] >= 0} {
        error "Filename pattern must not contain path separators; use path to select a directory"
    }

    set relativePath [dict getdef $arguments path "."]
    set entryType [dict getdef $arguments type all]
    set startPath [::PluginSupport::resolveWorkspacePath \
        $workspaceRoot $relativePath]
    if {![file isdirectory $startPath]} {
        error "Directory does not exist: $relativePath"
    }

    set pending [list $startPath]
    set matches {}
    set maximumMatches 200
    while {[llength $pending] > 0
            && [llength $matches] < $maximumMatches} {
        set directory [lindex $pending end]
        set pending [lrange $pending 0 end-1]
        if {![::PluginSupport::isWithin $directory $workspaceRoot]} {
            continue
        }
        foreach candidate [concat \
                [glob -nocomplain -directory $directory *] \
                [glob -nocomplain -directory $directory .*]] {
            set name [file tail $candidate]
            if {$name in {. ..}} {
                continue
            }
            set isDirectory [file isdirectory $candidate]
            if {$isDirectory && $name ne ".git"} {
                lappend pending $candidate
            }
            if {![string match -nocase $pattern $name]} {
                continue
            }
            if {$entryType eq "file" && $isDirectory} {
                continue
            }
            if {$entryType eq "directory" && !$isDirectory} {
                continue
            }
            set match [::plugins::find_files::relativePath \
                $workspaceRoot $candidate]
            if {$isDirectory} {
                append match /
            }
            lappend matches $match
        }
    }

    set matches [lsort -dictionary -unique $matches]
    if {[llength $matches] == 0} {
        return "No matching files or directories found."
    }
    return [join $matches "\n"]
}
