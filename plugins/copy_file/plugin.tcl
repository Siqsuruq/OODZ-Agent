namespace eval ::plugins::copy_file {}

proc ::plugins::copy_file::execute {workspaceRoot arguments settings} {
    set sourceRelative [string trim [dict get $arguments source]]
    set destinationRelative [string trim [dict get $arguments destination]]
    if {$sourceRelative eq "" || $destinationRelative eq ""} {
        error "Source and destination paths must not be empty"
    }

    set source [::PluginSupport::resolveWorkspacePath \
        $workspaceRoot $sourceRelative]
    set destination [::PluginSupport::resolveWorkspacePath \
        $workspaceRoot $destinationRelative]
    if {![file isfile $source]} {
        error "Source file does not exist: $sourceRelative"
    }
    if {[file exists $destination]} {
        error "Destination already exists: $destinationRelative"
    }
    if {![file isdirectory [file dirname $destination]]} {
        error "Destination parent directory does not exist: [file dirname $destinationRelative]"
    }

    file copy $source $destination
    return "Copied file: $sourceRelative -> $destinationRelative"
}
