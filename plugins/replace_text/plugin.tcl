namespace eval ::plugins::replace_text {}

proc ::plugins::replace_text::execute {workspaceRoot arguments settings} {
    set relativePath [dict get $arguments path]
    set oldText [dict get $arguments old_text]
    set newText [dict get $arguments new_text]
    if {[string trim $relativePath] eq ""} {error "File path must not be empty"}
    if {$oldText eq ""} {error "old_text must not be empty"}
    if {$oldText eq $newText} {error "Replacement would not change the file"}
    set path [::PluginSupport::resolveWorkspacePath $workspaceRoot $relativePath]
    if {![file isfile $path]} {error "File does not exist: $relativePath"}
    set channel [open $path r]
    try {
        fconfigure $channel -encoding utf-8
        set content [read $channel]
    } finally {close $channel}
    set first [string first $oldText $content]
    if {$first < 0} {error "old_text was not found in: $relativePath"}
    set second [string first $oldText $content \
        [expr {$first + [string length $oldText]}]]
    if {$second >= 0} {error "old_text appears more than once in: $relativePath"}
    set updated [string replace $content $first \
        [expr {$first + [string length $oldText] - 1}] $newText]
    set temporaryChannel [file tempfile temporaryPath \
        [file join [file dirname $path] .oodz-replace-XXXXXX]]
    try {
        fconfigure $temporaryChannel -encoding utf-8 -translation lf
        puts -nonewline $temporaryChannel $updated
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
    return "Replaced text in: $relativePath"
}
