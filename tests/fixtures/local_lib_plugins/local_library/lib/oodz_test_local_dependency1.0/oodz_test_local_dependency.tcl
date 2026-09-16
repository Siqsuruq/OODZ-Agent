namespace eval ::oodz_test_local_dependency {}

proc ::oodz_test_local_dependency::message {} {
    return "loaded plugin-local package"
}

package provide oodz_test_local_dependency 1.0
