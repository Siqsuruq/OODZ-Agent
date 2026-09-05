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
