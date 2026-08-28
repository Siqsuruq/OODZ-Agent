namespace eval ::plugins::random_string {}

proc ::plugins::random_string::execute {workspaceRoot arguments settings} {
    set length 16
    if {[dict exists $arguments length]} {
        set length [dict get $arguments length]
    }
    set maximum 4096
    if {[dict exists $settings max_length]} {
        set maximum [dict get $settings max_length]
    }
    if {![string is entier -strict $maximum] || $maximum <= 0} {
        error "random_string max_length setting must be a positive integer"
    }
    if {![string is entier -strict $length] || $length <= 0} {
        error "random_string length must be a positive integer"
    }
    if {$length > $maximum} {
        error "random_string length exceeds configured limit: $maximum"
    }

    set alphabetName alphanumeric
    if {[dict exists $arguments alphabet]} {
        set alphabetName [string tolower [string trim [dict get $arguments alphabet]]]
    }
    set alphabets [dict create alphanumeric abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 lowercase abcdefghijklmnopqrstuvwxyz uppercase ABCDEFGHIJKLMNOPQRSTUVWXYZ hex 0123456789abcdef]
    if {![dict exists $alphabets $alphabetName]} {
        error "random_string alphabet must be one of: alphanumeric, lowercase, uppercase, hex"
    }
    set characters [dict get $alphabets $alphabetName]
    set characterCount [string length $characters]
    set result ""
    for {set index 0} {$index < $length} {incr index} {
        append result [string index $characters [expr {int(rand() * $characterCount)}]]
    }
    return $result
}

