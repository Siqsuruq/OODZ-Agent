namespace eval ::plugins::apply_patch {}

proc ::plugins::apply_patch::validateChanges {rawChanges} {
    set count [llength $rawChanges]
    if {$count < 1 || $count > 100} {
        error "apply_patch changes must contain between 1 and 100 items"
    }
    set changes {}
    set index 0
    foreach change $rawChanges {
        incr index
        if {[catch {dict size $change}]} {
            error "apply_patch change $index must be an object"
        }
        set keys [lsort [dict keys $change]]
        if {$keys ne [list new_text old_text]} {
            error "apply_patch change $index must contain only old_text and new_text"
        }
        set oldText [dict get $change old_text]
        set newText [dict get $change new_text]
        if {$oldText eq ""} {
            error "apply_patch change $index old_text must not be empty"
        }
        lappend changes [list $oldText $newText]
    }
    return $changes
}

proc ::plugins::apply_patch::execute {workspaceRoot arguments settings} {
    set relativePath [string trim [dict get $arguments path]]
    if {$relativePath eq ""} {
        error "File path must not be empty"
    }
    set changes [::plugins::apply_patch::validateChanges \
        [dict get $arguments changes]]
    set path [::PluginSupport::resolveWorkspacePath $workspaceRoot $relativePath]
    if {![file isfile $path]} {
        error "File does not exist: $relativePath"
    }

    set channel [open $path r]
    try {
        fconfigure $channel -encoding utf-8
        set content [read $channel]
    } finally {
        close $channel
    }

    set changeIndex 0
    foreach change $changes {
        incr changeIndex
        lassign $change search replacement
        set first [string first $search $content]
        if {$first < 0} {
            error "apply_patch change $changeIndex old_text was not found in: $relativePath"
        }
        set second [string first $search $content \
            [expr {$first + [string length $search]}]]
        if {$second >= 0} {
            error "apply_patch change $changeIndex old_text appears more than once in: $relativePath"
        }
        set content [string replace $content $first \
            [expr {$first + [string length $search] - 1}] $replacement]
    }

    set temporaryChannel [file tempfile temporaryPath \
        [file join [file dirname $path] .oodz-patch-XXXXXX]]
    try {
        fconfigure $temporaryChannel -encoding utf-8 -translation lf
        puts -nonewline $temporaryChannel $content
        close $temporaryChannel
        set temporaryChannel ""
        if {![catch {file attributes $path -permissions} permissions]} {
            catch {file attributes $temporaryPath -permissions $permissions}
        }
        file rename -force $temporaryPath $path
    } finally {
        if {$temporaryChannel ne ""} {
            close $temporaryChannel
        }
        if {[file exists $temporaryPath]} {
            file delete $temporaryPath
        }
    }
    return "Applied changes to: $relativePath ([llength $changes] change(s))"
}
