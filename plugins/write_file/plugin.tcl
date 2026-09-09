namespace eval ::plugins::write_file {}

proc ::plugins::write_file::execute {workspaceRoot arguments settings} {
    set relativePath [dict get $arguments path]
    set path [::PluginSupport::resolveWorkspacePath \
        $workspaceRoot $relativePath]
    if {![file isfile $path]} {
        error "File does not exist: $relativePath; use create_file for a new file"
    }
    set temporaryChannel [file tempfile temporaryPath \
        [file join [file dirname $path] .oodz-write-XXXXXX]]
    try {
        fconfigure $temporaryChannel -encoding utf-8 -translation lf
        puts -nonewline $temporaryChannel [dict get $arguments content]
        close $temporaryChannel
        set temporaryChannel ""
        if {![catch {file attributes $path -permissions} permissions]} {
            catch {file attributes $temporaryPath -permissions $permissions}
        }
        file rename -force $temporaryPath $path
    } finally {
        if {$temporaryChannel ne ""} {close $temporaryChannel}
        if {[file exists $temporaryPath]} {file delete $temporaryPath}
    }
    return "Rewrote file: $relativePath"
}
