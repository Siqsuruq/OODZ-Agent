source [file join [file dirname [file dirname [info script]]] fossil_common.tcl]

namespace eval ::plugins::fossil_branch_new {}

proc ::plugins::fossil_branch_new::boundedValue {
    arguments settings key settingName
} {
    set maximum 200
    if {[dict exists $settings $settingName]} {
        set maximum [::plugins::fossil_common::positiveInteger \
            [dict get $settings $settingName] \
            "fossil_branch_new $settingName setting"]
    }
    set value [dict get $arguments $key]
    if {[string trim $value] eq ""} {
        error "fossil_branch_new $key must not be empty"
    }
    if {[string length $value] > $maximum} {
        error "fossil_branch_new $key exceeds configured limit: $maximum"
    }
    if {[string first "\x00" $value] >= 0} {
        error "fossil_branch_new $key contains a null character"
    }
    return $value
}

proc ::plugins::fossil_branch_new::execute {
    workspaceRoot arguments settings
} {
    set name [::plugins::fossil_branch_new::boundedValue \
        $arguments $settings name max_name_chars]
    set basis [::plugins::fossil_branch_new::boundedValue \
        $arguments $settings basis max_basis_chars]
    ::plugins::fossil_common::run $settings \
        [list branch new --nosync -- $name $basis]
}
