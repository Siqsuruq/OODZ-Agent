namespace eval ::plugins::create_file {}

proc ::plugins::create_file::execute {workspaceRoot arguments settings} {
    set newfile [string trim [dict get $arguments newfile]]

    if {$newfile eq "" } {
        error "New file paths must not be empty"
    }

    set source [::PluginSupport::resolveWorkspacePath $workspaceRoot $newfile]
    
	close [open $source a]
    return "File created: $newfile"
}
