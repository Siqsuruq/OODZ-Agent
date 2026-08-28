namespace eval ::plugins::system_info {}

proc ::plugins::system_info::platformValue {name {default unknown}} {
    if {[info exists ::tcl_platform($name)]} {
        return $::tcl_platform($name)
    }
    return $default
}

proc ::plugins::system_info::platform {} {
    set os [string tolower [::plugins::system_info::platformValue os]]
    if {[string match "windows*" $os]} {
        return windows
    }
    if {$os in {linux freebsd}} {
        return $os
    }
    return $os
}

proc ::plugins::system_info::execute {workspaceRoot arguments settings} {
    set threadVersion unavailable
    catch {set threadVersion [package require Thread 3.0]}
    set fields [list \
        "Operating system" [::plugins::system_info::platformValue os] \
        "OS version" [::plugins::system_info::platformValue osVersion] \
        "Platform" [::plugins::system_info::platform] \
        "Architecture" [::plugins::system_info::platformValue machine] \
        "Pointer size" "[::plugins::system_info::platformValue pointerSize] bytes" \
        "Tcl version" [info patchlevel] \
        "Tcl engine" [::plugins::system_info::platformValue engine Tcl] \
        "Thread package" $threadVersion \
        "Tcl executable" [file normalize [info nameofexecutable]] \
        "Workspace" [file normalize $workspaceRoot]]
    set lines {}
    foreach {label value} $fields {
        lappend lines "${label}: $value"
    }
    return [join $lines "\n"]
}
