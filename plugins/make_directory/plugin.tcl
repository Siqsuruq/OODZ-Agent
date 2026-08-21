namespace eval ::plugins::make_directory {}

proc ::plugins::make_directory::execute {workspaceRoot arguments settings} {
    set relativePath [string trim [dict get $arguments path]]
    if {$relativePath eq "" || $relativePath eq "."} {
        error "Directory path must identify a new workspace directory"
    }

    set path [::PluginSupport::resolveWorkspacePath \
        $workspaceRoot $relativePath]
    if {[file exists $path]} {
        if {[file isdirectory $path]} {
            return "Directory already exists: $relativePath"
        }
        error "Target exists and is not a directory: $relativePath"
    }

    file mkdir $path
    return "Created directory: $relativePath"
}
