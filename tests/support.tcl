#!/usr/bin/env tclsh

package require Tcl 9.0
package require tcltest 2.5

namespace import ::tcltest::*

if {[llength $::argv] > 0} {
    ::tcltest::configure {*}$::argv
}

set testsDir [file dirname [file normalize [info script]]]
set projectDir [file dirname $testsDir]

# Fossil refuses to open a checkout nested inside another checkout. Tcltest's
# default temporary directory is the current working directory, so choose a
# system temporary directory unless the caller supplied -tmpdir explicitly.
set ownedTestTemporaryDirectory ""
if {[lsearch -exact $::argv -tmpdir] < 0} {
    set ownedTestTemporaryDirectory [file tempdir oodz-agent-tests]
    ::tcltest::configure -tmpdir $ownedTestTemporaryDirectory
}

lappend auto_path [file join $projectDir lib]
package require tLogger

# runAllTests executes each .test file in a child process. Application logs on
# stderr make Tcl's pipeline close report an error even when every assertion
# passed, so keep diagnostics in the test temporary directory.
set testLogPath [file join [::tcltest::temporaryDirectory] "oodz-tests-[pid].log"]
::tLogger setAppenderFactory [list ::FileAppender new $testLogPath]

source [file join $projectDir main.tcl]

testConstraint fossilAvailable [expr {[auto_execok fossil] ne ""}]

::oo::class create ::FakeLLMClient {
    variable calls responses

    constructor {{configuredResponses {"fake response"}}} {
        set calls {}
        set responses $configuredResponses
    }

    method query {systemPrompt messages} {
        lappend calls [list $systemPrompt $messages]
        set response [lindex $responses 0]
        set responses [lrange $responses 1 end]
        return $response
    }

    method queryMessage {systemPrompt messages tools} {
        set content [my query $systemPrompt $messages]
        return [dict create role assistant content $content]
    }

    method getCalls {} {
        return $calls
    }
}

::oo::class create ::StructuredFakeLLMClient {
    variable calls responses

    constructor {configuredResponses} {
        set calls {}
        set responses $configuredResponses
    }

    method queryMessage {systemPrompt messages tools} {
        lappend calls [list $systemPrompt $messages $tools]
        set response [lindex $responses 0]
        set responses [lrange $responses 1 end]
        return $response
    }

    method getCalls {} {
        return $calls
    }
}

::oo::class create ::FailingLLMClient {
    method query {systemPrompt messages} {
        error "fake failure"
    }

    method queryMessage {systemPrompt messages tools} {
        error "fake failure"
    }
}

::oo::class create ::FakeConfig {
    variable values

    constructor {{configValues {}}} {
        set values $configValues
    }

    method get {key {default ""}} {
        if {[dict exists $values $key]} {
            return [dict get $values $key]
        }
        return $default
    }
}

::oo::class create ::FakeTransport {
    variable outcomes requests waits

    constructor {configuredOutcomes} {
        set outcomes $configuredOutcomes
        set requests {}
        set waits {}
    }

    method post {url payload headers timeout} {
        lappend requests [list $url $payload $headers $timeout]
        set outcome [lindex $outcomes 0]
        set outcomes [lrange $outcomes 1 end]

        if {[dict exists $outcome error]} {
            error [dict get $outcome error]
        }
        return $outcome
    }

    method getRequests {} {
        return $requests
    }

    method wait {milliseconds} {
        lappend waits $milliseconds
    }

    method getWaits {} {
        return $waits
    }
}

::oo::class create ::FakeStreamingTransport {
    variable events payload fallbackBody postCount streamResponse streamError

    constructor {
        configuredEvents {configuredFallbackBody ""} {configuredStreamResponse ""}
        {configuredStreamError ""}
    } {
        set events $configuredEvents
        set payload ""
        set fallbackBody $configuredFallbackBody
        set postCount 0
        set streamResponse $configuredStreamResponse
        set streamError $configuredStreamError
    }

    method postStream {url requestPayload headers timeout eventCallback} {
        set payload $requestPayload
        if {$streamError ne ""} {
            error $streamError
        }
        foreach event $events {
            {*}$eventCallback $event
        }
        if {$streamResponse ne ""} {
            return $streamResponse
        }
        return [dict create status ok code 200 body ""]
    }

    method getPayload {} {
        return $payload
    }

    method post {url requestPayload headers timeout} {
        incr postCount
        return [dict create status ok code 200 body $fallbackBody]
    }

    method wait {milliseconds} {
        return
    }

    method getPostCount {} {
        return $postCount
    }
}

namespace eval ::ApprovalMock {
    variable approved 0
    variable calls {}

    proc decide {name arguments} {
        variable approved
        variable calls
        lappend calls [list $name $arguments]
        return $approved
    }
}

namespace eval ::RunnerMock {
    variable calls {}

    proc execute {command timeout maxOutput} {
        variable calls
        lappend calls [list $command $timeout $maxOutput]
        return [dict create \
            status exited exit_code 0 output "sandboxed Tcl output" \
            duration_ms 1 timed_out false output_truncated false]
    }
}

namespace eval ::StreamCapture {
    variable content ""

    proc append {fragment} {
        variable content
        ::append content $fragment
    }
}

namespace eval ::SSECapture {
    variable events {}

    proc add {event} {
        variable events
        lappend events $event
    }
}


proc ::finishTests {} {
    set failedCount $::tcltest::numTests(Failed)
    if {[info exists ::testLogPath] && [file exists $::testLogPath]} {
        file delete -force $::testLogPath
    }
    cleanupTests
    if {$::ownedTestTemporaryDirectory ne ""
            && [file exists $::ownedTestTemporaryDirectory]} {
        file delete -force $::ownedTestTemporaryDirectory
    }
    if {$failedCount > 0} {
        exit 1
    }
}
