namespace eval ::plugins::create_file {}

proc ::plugins::create_file::execute {workspaceRoot arguments settings} {
    set relativePath [string trim [dict get $arguments path]]
    if {$relativePath eq ""} {
        error "File path must not be empty"
    }
    set path [::PluginSupport::resolveWorkspacePath $workspaceRoot $relativePath]
    if {[file exists $path]} {
        error "File already exists: $relativePath"
    }
    if {![file isdirectory [file dirname $path]]} {
        error "Parent directory does not exist: [file dirname $relativePath]"
    }
    set channel [open $path {WRONLY CREAT EXCL}]
    try {
        fconfigure $channel -encoding utf-8 -translation lf
        puts -nonewline $channel [dict get $arguments content]
    } finally {
        close $channel
    }
    return "Created file: $relativePath"
}
