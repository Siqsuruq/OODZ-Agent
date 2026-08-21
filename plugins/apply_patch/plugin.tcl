namespace eval ::plugins::apply_patch {}

proc ::plugins::apply_patch::parse {patch} {
    set start "<<<<<<< SEARCH\n"
    set middle "\n=======\n"
    set finish "\n>>>>>>> REPLACE"
    set changes {}
    set position 0
    while {$position < [string length $patch]} {
        if {[string range $patch $position \
                [expr {$position + [string length $start] - 1}]] ne $start} {
            error "Invalid patch: expected <<<<<<< SEARCH block"
        }
        set searchStart [expr {$position + [string length $start]}]
        set separator [string first $middle $patch $searchStart]
        if {$separator < 0} {
            error "Invalid patch: missing ======= separator"
        }
        set replacementStart [expr {$separator + [string length $middle]}]
        set end [string first $finish $patch $replacementStart]
        if {$end < 0} {
            error "Invalid patch: missing >>>>>>> REPLACE marker"
        }
        set search [string range $patch $searchStart [expr {$separator - 1}]]
        set replacement [string range $patch $replacementStart [expr {$end - 1}]]
        if {$search eq ""} {
            error "Invalid patch: SEARCH text must not be empty"
        }
        lappend changes [list $search $replacement]
        set position [expr {$end + [string length $finish]}]
        if {$position < [string length $patch]} {
            if {[string index $patch $position] ne "\n"} {
                error "Invalid patch: unexpected text after REPLACE marker"
            }
            incr position
        }
    }
    if {[llength $changes] == 0} {
        error "Patch must contain at least one SEARCH/REPLACE block"
    }
    return $changes
}

proc ::plugins::apply_patch::execute {workspaceRoot arguments settings} {
    set relativePath [string trim [dict get $arguments path]]
    if {$relativePath eq ""} {
        error "File path must not be empty"
    }
    set changes [::plugins::apply_patch::parse [dict get $arguments patch]]
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

    foreach change $changes {
        lassign $change search replacement
        set first [string first $search $content]
        if {$first < 0} {
            error "Patch SEARCH text was not found in: $relativePath"
        }
        set second [string first $search $content \
            [expr {$first + [string length $search]}]]
        if {$second >= 0} {
            error "Patch SEARCH text appears more than once in: $relativePath"
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
    return "Applied patch to: $relativePath ([llength $changes] change(s))"
}
