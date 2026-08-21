namespace eval ::plugins::list_files {}

proc ::plugins::list_files::execute {workspaceRoot arguments settings} {
    set relativePath "."
    if {[dict exists $arguments path]} {
        set relativePath [dict get $arguments path]
    }
    set path [::PluginSupport::resolveWorkspacePath \
        $workspaceRoot $relativePath]
    if {![file isdirectory $path]} {
        error "Directory does not exist: $relativePath"
    }

    set entries {}
    foreach candidate [concat \
            [glob -nocomplain -directory $path *] \
            [glob -nocomplain -directory $path .*]] {
        set tail [file tail $candidate]
        if {$tail in {. ..}} {
            continue
        }
        if {[file isdirectory $candidate]} {
            append tail /
        }
        lappend entries $tail
    }
    return [join [lsort -unique $entries] "\n"]
}
