package require json
package require json::write

::oo::class create tDiagnostics {
    variable enabled path maxEvents events

    constructor {configuredPath {configuredEnabled true} {configuredMaxEvents 5000}} {
        if {![string is boolean -strict $configuredEnabled]} {
            error "Diagnostics.enabled must be boolean"
        }
        if {![string is entier -strict $configuredMaxEvents]
                || $configuredMaxEvents < 100} {
            error "Diagnostics.max_events must be an integer of at least 100"
        }
        set enabled [expr {$configuredEnabled ? 1 : 0}]
        set path [file normalize $configuredPath]
        set maxEvents $configuredMaxEvents
        set events {}
        if {$enabled} {my load}
    }

    method encodeEvent {event} {
        set fields {}
        dict for {name value} $event {
            if {[string is entier -strict $value]
                    || [string is double -strict $value]} {
                lappend fields $name $value
            } else {
                lappend fields $name [::json::write string $value]
            }
        }
        set previousIndent [::json::write indented]
        ::json::write indented 0
        try {
            return [::json::write object {*}$fields]
        } finally {
            ::json::write indented $previousIndent
        }
    }

    method load {} {
        if {![file exists $path]} {return}
        set channel [open $path r]
        try {
            fconfigure $channel -encoding utf-8
            while {[gets $channel line] >= 0} {
                if {[string trim $line] eq ""} {continue}
                if {![catch {::json::json2dict $line} event]
                        && ![catch {dict exists $event type} hasType]
                        && $hasType} {
                    lappend events $event
                }
            }
        } finally {
            close $channel
        }
        if {[llength $events] > $maxEvents} {
            set events [lrange $events end-[expr {$maxEvents - 1}] end]
            my rewrite
        }
    }

    method rewrite {} {
        file mkdir [file dirname $path]
        set channel [file tempfile temporaryPath \
            [file join [file dirname $path] .oodz-diagnostics-XXXXXX]]
        try {
            fconfigure $channel -encoding utf-8 -translation lf
            foreach event $events {puts $channel [my encodeEvent $event]}
            close $channel
            set channel ""
            file rename -force $temporaryPath $path
        } finally {
            if {$channel ne ""} {close $channel}
            if {[file exists $temporaryPath]} {file delete $temporaryPath}
        }
    }

    method record {type {details {}}} {
        if {!$enabled} {return}
        set event [dict create timestamp_ms [clock milliseconds] type $type]
        dict for {name value} $details {dict set event $name $value}
        lappend events $event
        if {[llength $events] > $maxEvents} {
            set events [lrange $events end-[expr {$maxEvents - 1}] end]
            my rewrite
            return
        }
        file mkdir [file dirname $path]
        set channel [open $path a]
        try {
            fconfigure $channel -encoding utf-8 -translation lf
            puts $channel [my encodeEvent $event]
        } finally {
            close $channel
        }
    }

    method events {} {return $events}

    method clear {} {
        set events {}
        if {[file exists $path]} {file delete $path}
    }

    method summary {} {
        set result [dict create requests 0 request_failures 0 tool_calls 0 \
            tool_failures 0 skipped_calls 0 compactions 0 iterations 0 \
            input_tokens 0 output_tokens 0 total_tokens 0 request_duration_ms 0]
        set tools [dict create]
        set failedTools [dict create]
        foreach event $events {
            set type [dict get $event type]
            switch -- $type {
                llm_request {dict incr result requests}
                llm_response {
                    if {[dict exists $event duration_ms]} {
                        dict incr result request_duration_ms [dict get $event duration_ms]
                    }
                }
                llm_error {dict incr result request_failures}
                iteration {dict incr result iterations}
                tool_call {
                    dict incr result tool_calls
                    set name [dict getdef $event name unknown]
                    dict incr tools $name
                }
                tool_failure {
                    dict incr result tool_failures
                    set name [dict getdef $event name unknown]
                    dict incr failedTools $name
                }
                tool_skipped {dict incr result skipped_calls}
                context_compaction {dict incr result compactions}
                usage {
                    foreach field {input_tokens output_tokens total_tokens} {
                        if {[dict exists $event $field]
                                && [string is entier -strict [dict get $event $field]]} {
                            dict incr result $field [dict get $event $field]
                        }
                    }
                }
            }
        }
        dict set result tools $tools
        dict set result failed_tools $failedTools
        return $result
    }
}
