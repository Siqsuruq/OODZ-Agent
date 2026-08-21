source [file join [file dirname [file dirname [info script]]] fossil_common.tcl]

namespace eval ::plugins::fossil_commit {}

proc ::plugins::fossil_commit::execute {
    workspaceRoot arguments settings
} {
    set maxMessageChars 1000
    if {[dict exists $settings max_message_chars]} {
        set maxMessageChars [dict get $settings max_message_chars]
    }
    if {![string is entier -strict $maxMessageChars]
            || $maxMessageChars <= 0} {
        error "fossil_commit max_message_chars setting must be a positive integer"
    }
    set message [dict get $arguments message]
    if {[string trim $message] eq ""} {
        error "fossil_commit message must not be empty"
    }
    if {[string length $message] > $maxMessageChars} {
        error "fossil_commit message exceeds configured limit: $maxMessageChars"
    }
    if {[string first "\x00" $message] >= 0} {
        error "fossil_commit message contains a null character"
    }
    ::plugins::fossil_common::run $settings \
        [list commit --nosync --no-prompt -m $message]
}
