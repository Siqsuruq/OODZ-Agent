namespace eval ::plugins::list_folders {}

proc ::plugins::list_folders::execute {workspaceRoot arguments settings} {
    set relativePath "."
    if {[dict exists $arguments path]} {
        set relativePath [string trim [dict get $arguments path]]
        if {$relativePath eq ""} {
            set relativePath "."
        }
    }
    set path [::PluginSupport::resolveWorkspacePath $workspaceRoot $relativePath]
    if {![file isdirectory $path]} {
        error "Directory does not exist: $relativePath"
    }

    set folders {}
    foreach candidate [concat [glob -nocomplain -types d -directory $path *] [glob -nocomplain -types d -directory $path .*]] {
        set tail [file tail $candidate]
        if {$tail ni {. ..}} {
            lappend folders "${tail}/"
        }
    }
    return [join [lsort -unique $folders] "\n"]
}

