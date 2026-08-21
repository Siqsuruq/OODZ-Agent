source [file join [file dirname [file dirname [info script]]] fossil_common.tcl]

namespace eval ::plugins::fossil_stash_save {}

proc ::plugins::fossil_stash_save::execute {
    workspaceRoot arguments settings
} {
    set maximum 1000
    if {[dict exists $settings max_comment_chars]} {
        set maximum [::plugins::fossil_common::positiveInteger \
            [dict get $settings max_comment_chars] \
            "fossil_stash_save max_comment_chars setting"]
    }
    set comment [dict get $arguments comment]
    if {[string trim $comment] eq ""} {
        error "fossil_stash_save comment must not be empty"
    }
    if {[string length $comment] > $maximum} {
        error "fossil_stash_save comment exceeds configured limit: $maximum"
    }
    if {[string first "\x00" $comment] >= 0} {
        error "fossil_stash_save comment contains a null character"
    }
    ::plugins::fossil_common::run $settings \
        [list stash save --comment $comment]
}
