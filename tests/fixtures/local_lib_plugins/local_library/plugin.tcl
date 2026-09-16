package require oodz_test_local_dependency 1.0

namespace eval ::plugins::local_library {}

proc ::plugins::local_library::execute {workspaceRoot arguments settings} {
    return [::oodz_test_local_dependency::message]
}
