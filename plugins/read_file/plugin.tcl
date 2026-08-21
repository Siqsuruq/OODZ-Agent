namespace eval ::plugins::read_file {}

proc ::plugins::read_file::execute {workspaceRoot arguments settings} {
    set path [::PluginSupport::resolveWorkspacePath \
        $workspaceRoot [dict get $arguments path]]
    if {![file isfile $path]} {
        error "File does not exist: [dict get $arguments path]"
    }

    set channel [open $path r]
    try {
        fconfigure $channel -encoding utf-8
        return [read $channel]
    } finally {
        close $channel
    }
}
