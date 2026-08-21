namespace eval ::plugins::delete_file {}

proc ::plugins::delete_file::execute {workspaceRoot arguments settings} {
    set relativePath [string trim [dict get $arguments path]]
    if {$relativePath eq ""} {
        error "File path must not be empty"
    }

    set path [::PluginSupport::resolveWorkspacePath \
        $workspaceRoot $relativePath]
    if {![file exists $path]} {
        error "File does not exist: $relativePath"
    }
    if {![file isfile $path]} {
        error "Path is not a file: $relativePath"
    }

    file delete $path
    return "Deleted file: $relativePath"
}
