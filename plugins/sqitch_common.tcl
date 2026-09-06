namespace eval ::plugins::sqitch_common {}

proc ::plugins::sqitch_common::executable {settings} {
    if {[dict exists $settings executable]
            && [string trim [dict get $settings executable]] ne ""} {
        return [dict get $settings executable]
    }
    return sqitch
}

proc ::plugins::sqitch_common::run {settings arguments} {
    ::PluginSupport::formatProcessResult \
        [::PluginSupport::runConfiguredCommand \
            [::plugins::sqitch_common::executable $settings] $arguments]
}

proc ::plugins::sqitch_common::boundedInteger {
    value label minimum maximum
} {
    if {![string is entier -strict $value]
            || $value < $minimum || $value > $maximum} {
        error "$label must be an integer from $minimum to $maximum"
    }
    return $value
}

proc ::plugins::sqitch_common::objectIdentifier {value label} {
    set value [string trim $value]
    if {$value eq ""} {
        error "$label must not be empty"
    }
    if {[string length $value] > 200} {
        error "$label exceeds 200 characters"
    }
    if {![regexp {^[A-Za-z0-9@][A-Za-z0-9_.@/+:-]*$} $value]} {
        error "$label contains unsupported characters"
    }
    return $value
}

proc ::plugins::sqitch_common::changeName {value label} {
    set value [string trim $value]
    if {$value eq ""} {
        error "$label must not be empty"
    }
    if {[string length $value] > 200} {
        error "$label exceeds 200 characters"
    }
    if {![regexp {^[A-Za-z0-9][A-Za-z0-9_.+-]*$} $value]} {
        error "$label contains unsupported characters"
    }
    return $value
}

proc ::plugins::sqitch_common::note {value label} {
    set value [string trim $value]
    if {$value eq ""} {
        error "$label must not be empty"
    }
    if {[string length $value] > 500} {
        error "$label exceeds 500 characters"
    }
    if {[regexp {[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]} $value]} {
        error "$label must not contain control characters"
    }
    return $value
}
