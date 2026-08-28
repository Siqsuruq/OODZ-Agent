namespace eval ::plugins::zip {}

proc ::plugins::zip::execute {workspaceRoot arguments settings} {
    set sourceRelative [string trim [dict get $arguments source]]
    set destinationRelative [string trim [dict get $arguments destination]]
    if {$sourceRelative eq "" || $destinationRelative eq ""} {
        error "ZIP source and destination paths must not be empty"
    }
    if {[string tolower [file extension $destinationRelative]] ne ".zip"} {
        error "ZIP destination must use the .zip extension"
    }

    set source [::PluginSupport::resolveWorkspacePath $workspaceRoot $sourceRelative]
    set destination [::PluginSupport::resolveWorkspacePath $workspaceRoot $destinationRelative]
    if {![file isdirectory $source]} {
        error "ZIP source directory does not exist: $sourceRelative"
    }
    if {[file exists $destination]} {
        error "ZIP destination already exists: $destinationRelative"
    }
    if {[::PluginSupport::isWithin $destination $source]} {
        error "ZIP destination must not be inside the source directory"
    }
    if {![file isdirectory [file dirname $destination]]} {
        error "ZIP destination parent directory does not exist: [file dirname $destinationRelative]"
    }

    zipfs mkzip $destination $source $source
    return "Created ZIP archive: $sourceRelative -> $destinationRelative"
}
