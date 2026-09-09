namespace eval ::plugins::delete_directory {}

proc ::plugins::delete_directory::execute {workspaceRoot arguments settings} {
    set relativePath [string trim [dict get $arguments path]]
    if {$relativePath eq ""} {
        error "Directory path must not be empty"
    }

    set path [::PluginSupport::resolveWorkspacePath $workspaceRoot $relativePath]
    if {$path eq [file normalize $workspaceRoot]} {
        error "The workspace root cannot be deleted"
    }
    if {![file exists $path]} {
        error "Directory does not exist: $relativePath"
    }
    if {![file isdirectory $path]} {
        error "Path is not a directory: $relativePath"
    }

    set recursive [dict getdef $arguments recursive false]
    if {!$recursive} {
        set entries [concat \
            [glob -nocomplain -directory $path *] \
            [glob -nocomplain -directory $path .*]]
        set entries [lsearch -all -inline -not -exact $entries \
            [file join $path .]]
        set entries [lsearch -all -inline -not -exact $entries \
            [file join $path ..]]
        if {[llength $entries] > 0} {
            error "Directory is not empty: $relativePath; use recursive=true to delete its contents"
        }
        file delete $path
        return "Deleted directory: $relativePath"
    }

    file delete -force $path
    return "Deleted directory recursively: $relativePath"
}
