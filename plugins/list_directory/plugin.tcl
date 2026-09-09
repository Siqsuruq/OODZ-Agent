namespace eval ::plugins::list_directory {}

proc ::plugins::list_directory::execute {workspaceRoot arguments settings} {
    set relativePath [string trim [dict getdef $arguments path "."]]
    if {$relativePath eq ""} {set relativePath "."}
    set path [::PluginSupport::resolveWorkspacePath $workspaceRoot $relativePath]
    if {![file isdirectory $path]} {error "Directory does not exist: $relativePath"}
    set entries {}
    foreach candidate [concat \
            [glob -nocomplain -directory $path *] \
            [glob -nocomplain -directory $path .*]] {
        set tail [file tail $candidate]
        if {$tail in {. ..}} {continue}
        if {[file isdirectory $candidate]} {append tail /}
        lappend entries $tail
    }
    if {[llength $entries] == 0} {return "Directory is empty."}
    return [join [lsort -dictionary -unique $entries] "\n"]
}
