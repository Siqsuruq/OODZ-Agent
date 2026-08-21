namespace eval ::plugins::write_file {}

proc ::plugins::write_file::execute {workspaceRoot arguments settings} {
    set relativePath [dict get $arguments path]
    set path [::PluginSupport::resolveWorkspacePath \
        $workspaceRoot $relativePath]
    set parent [file dirname $path]
    if {![file isdirectory $parent]} {
        error "Parent directory does not exist: [file dirname $relativePath]"
    }

    set channel [open $path w]
    try {
        fconfigure $channel -encoding utf-8
        puts -nonewline $channel [dict get $arguments content]
    } finally {
        close $channel
    }
    return "Wrote file: $relativePath"
}
