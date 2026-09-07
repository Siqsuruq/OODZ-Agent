source [file join [file dirname [file dirname [info script]]] fossil_common.tcl]

namespace eval ::plugins::fossil_clone {}

proc ::plugins::fossil_clone::execute {
    workspaceRoot arguments settings
} {
    set url [string trim [dict get $arguments url]]
    if {[string length $url] > 2048} {
        error "fossil_clone URL exceeds 2048 characters"
    }
    if {[regexp {[[:space:]\x00-\x1f\x7f]} $url]
            || ![regexp -nocase {^https?://([^/?#]+)(?:/[^?#]*)?$} \
                $url -> authority]} {
        error "fossil_clone URL must be HTTP(S) without whitespace, a query, or fragment"
    }
    if {[string first @ $authority] >= 0} {
        error "fossil_clone URL must not contain credentials"
    }

    set name [string trim [dict get $arguments name]]
    if {[string length $name] > 100
            || ![regexp {^[A-Za-z0-9][A-Za-z0-9_.-]*$} $name]
            || [string match -nocase *.fossil $name]} {
        error "fossil_clone name must be a safe base name without .fossil"
    }
    set repositoryName "$name.fossil"
    set repositoryPath [::PluginSupport::resolveWorkspacePath \
        $workspaceRoot $repositoryName]
    set checkoutPath [::PluginSupport::resolveWorkspacePath \
        $workspaceRoot $name]
    foreach {path label} [list \
        $repositoryPath "repository database" \
        $checkoutPath "checkout directory"] {
        if {[file exists $path]} {
            error "fossil_clone $label already exists: [file tail $path]"
        }
    }

    ::plugins::fossil_common::run $settings \
        [list clone $url $repositoryName --workdir $name]
}
