namespace eval ::plugins::move_directory {}

proc ::plugins::move_directory::execute {workspaceRoot arguments settings} {
    set sourceRelative [string trim [dict get $arguments source]]
    set destinationRelative [string trim [dict get $arguments destination]]
    if {$sourceRelative eq "" || $destinationRelative eq ""} {
        error "Source and destination paths must not be empty"
    }

    set root [file normalize $workspaceRoot]
    set source [::PluginSupport::resolveWorkspacePath \
        $workspaceRoot $sourceRelative]
    set destination [::PluginSupport::resolveWorkspacePath \
        $workspaceRoot $destinationRelative]
    if {$source eq $root} {
        error "The workspace root cannot be moved"
    }
    if {![file exists $source]} {
        error "Source directory does not exist: $sourceRelative"
    }
    if {![file isdirectory $source]} {
        error "Source path is not a directory: $sourceRelative"
    }
    if {[file exists $destination]} {
        error "Destination already exists: $destinationRelative"
    }
    if {[::PluginSupport::isWithin $destination $source]} {
        error "A directory cannot be moved inside itself: $destinationRelative"
    }
    if {![file isdirectory [file dirname $destination]]} {
        error "Destination parent directory does not exist: [file dirname $destinationRelative]"
    }

    file rename $source $destination
    return "Moved directory: $sourceRelative -> $destinationRelative"
}
