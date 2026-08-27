namespace eval ::plugins::fossil_common {}

proc ::plugins::fossil_common::executable {settings} {
    if {[dict exists $settings executable]
            && [string trim [dict get $settings executable]] ne ""} {
        return [dict get $settings executable]
    }
    return fossil
}

proc ::plugins::fossil_common::path {
    toolName workspaceRoot arguments {requireFile false}
} {
    set path [dict get $arguments path]
    if {[string trim $path] eq ""} {
        error "$toolName path must not be empty"
    }
    set resolved [::PluginSupport::resolveWorkspacePath \
        $workspaceRoot $path]
    if {$requireFile && ![file isfile $resolved]} {
        error "$toolName path is not an existing file: $path"
    }
    return $path
}

proc ::plugins::fossil_common::positiveInteger {value label} {
    if {![string is entier -strict $value] || $value <= 0} {
        error "$label must be a positive integer"
    }
    return $value
}

proc ::plugins::fossil_common::run {settings arguments} {
    ::PluginSupport::formatProcessResult \
        [::PluginSupport::runConfiguredCommand \
            [::plugins::fossil_common::executable $settings] $arguments]
}
