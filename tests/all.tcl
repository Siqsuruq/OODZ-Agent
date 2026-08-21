#!/usr/bin/env tclsh

package require Tcl 9.0
package require tcltest 2.5

namespace import ::tcltest::*

set testsDir [file dirname [file normalize [info script]]]
set projectDir [file dirname $testsDir]

lappend auto_path [file join $projectDir lib]
package require tLogger

source [file join $projectDir main.tcl]

testConstraint fossilAvailable [expr {[auto_execok fossil] ne ""}]

test zesty-1.1 {bundled terminal styling package is available} -body {
    list \
        [package present zesty] \
        [::terminalStyleEnabled test-channel] \
        [::styleTerminalText test-channel "plain text" {fg cyan}]
} -result [list 0.2 0 "plain text"]

test logging-1.1 {diagnostics can be routed to a file and read on demand} -body {
    set channel [file tempfile logPath]
    close $channel
    try {
        ::tLogger setAppenderFactory [list ::FileAppender new $logPath]
        set logger [::tLogger getLogger "RoutingTest"]
        $logger log info "routed diagnostic"
        ::tLogger setAppenderFactory [list ::ConsoleAppender new]
        set recent [::readRecentLog $logPath]
        expr {[string first "routed diagnostic" $recent] >= 0}
    } finally {
        ::tLogger setAppenderFactory [list ::ConsoleAppender new]
        file delete $logPath
    }
} -result 1

test config-ini-1.1 {supported INI backend saves and loads values} -body {
    set channel [file tempfile configPath]
    close $channel
    set config [::Config new]
    set loadedConfig [::Config new]
    set backend [::Config::Backend::Ini new]
    try {
        $config useBackend $backend $configPath
        $config set "Agent.name" "Test Agent"
        $config set "Agent.max_iterations" 8
        $config save

        $loadedConfig useBackend $backend $configPath
        $loadedConfig load
        list \
            [$loadedConfig get "Agent.name"] \
            [$loadedConfig get "Agent.max_iterations"] \
            [$loadedConfig get "missing" "fallback"]
    } finally {
        $loadedConfig destroy
        $config destroy
        $backend destroy
        file delete $configPath
    }
} -result [list "Test Agent" 8 "fallback"]

test release-config-1.1 {published config is placeholder-only and conservative} -body {
    set config [::Config new]
    set backend [::Config::Backend::Ini new]
    try {
        $config useBackend $backend \
            [file join $projectDir conf conf.example.ini]
        $config load
        set gitChannel [open [file join $projectDir .gitignore] r]
        set gitIgnore [read $gitChannel]
        close $gitChannel
        set fossilChannel [open [file join \
            $projectDir .fossil-settings ignore-glob] r]
        set fossilIgnore [read $fossilChannel]
        close $fossilChannel
        list \
            [$config get LLM.api_key] \
            [$config get Workspace.root] \
            [$config get Runner.enabled] \
            [expr {[string first "/conf/conf.ini" $gitIgnore] >= 0}] \
            [expr {[string first "conf/conf.ini" $fossilIgnore] >= 0}]
    } finally {
        $config destroy
        $backend destroy
    }
} -result [list replace-with-your-key . false 1 1]

test skill-registry-1.1 {skills are discovered with concise metadata} -body {
    set registry [::tSkillRegistry new [list \
        [file join $projectDir skills]]]
    try {
        set summaries [$registry summaries]
        set skill [$registry get create-oodz-class]
        list \
            [$registry names] \
            [dict get [lindex $summaries 0] name] \
            [expr {[string first "NX domain classes" \
                [dict get [lindex $summaries 0] description]] >= 0}] \
            [expr {[string first "oodz_lookup" \
                [dict get $skill instructions]] >= 0}] \
            [file tail [dict get $skill path]]
    } finally {
        $registry destroy
    }
} -result [list \
    [list create-oodz-class] create-oodz-class 1 1 create-oodz-class]

test skill-registry-1.1a {skill confinement uses shared path comparison} -body {
    set registry [::tSkillRegistry new {}]
    set root [file normalize [file join [temporaryDirectory] skills-root]]
    try {
        list \
            [$registry isWithin [file join $root sample] $root] \
            [$registry isWithin "${root}-other" $root]
    } finally {
        $registry destroy
    }
} -result {1 0}

test skill-registry-1.2 {invalid and duplicate skills are rejected} -body {
    set directory [file normalize [file join \
        [::tcltest::temporaryDirectory] skill-registry-[pid]]]
    set firstRoot [file join $directory first]
    set secondRoot [file join $directory second]
    file mkdir [file join $firstRoot sample-skill]
    file mkdir [file join $secondRoot sample-skill]
    foreach path [list \
            [file join $firstRoot sample-skill SKILL.md] \
            [file join $secondRoot sample-skill SKILL.md]] {
        set channel [open $path w]
        fconfigure $channel -encoding utf-8
        puts $channel [join [list \
            --- \
            {name: sample-skill} \
            {description: A test skill.} \
            --- \
            {} \
            {# Test instructions}] "\n"]
        close $channel
    }
    try {
        catch {
            ::tSkillRegistry new [list $firstRoot $secondRoot]
        } duplicateMessage
    } finally {
        file delete -force $directory
    }
    set duplicateMessage
} -result "Duplicate skill name: sample-skill"

test conversation-store-1.1 {conversation messages survive a JSON round trip} -body {
    set directory [file normalize [file join \
        [::tcltest::temporaryDirectory] conversation-store-[pid]]]
    file mkdir $directory
    set store [tConversationStore new [file join $directory history.json]]
    set toolCall [dict create \
        id call_1 \
        type function \
        function [dict create \
            name read_file \
            arguments {{"path":"café.txt"}}]]
    set messages [list \
        [dict create role user content "Read café.txt"] \
        [dict create role assistant content "" \
            reasoning_content "Need the file." tool_calls [list $toolCall]] \
        [dict create role tool content "line one\nline two" \
            tool_call_id call_1] \
        [dict create role assistant content "Done."]]
    try {
        set missing [$store load]
        $store save $messages
        set loaded [$store load]
        list $missing $loaded
    } finally {
        $store destroy
        file delete -force $directory
    }
} -result [list {} [list \
    [dict create role user content "Read café.txt"] \
    [dict create role assistant content "" \
        reasoning_content "Need the file." tool_calls [list [dict create \
            id call_1 type function function [dict create \
                name read_file arguments {{"path":"café.txt"}}]]]] \
    [dict create role tool content "line one\nline two" \
        tool_call_id call_1] \
    [dict create role assistant content "Done."]]]

test conversation-store-1.2 {invalid history fails without changing the file} -body {
    set channel [file tempfile historyPath]
    puts -nonewline $channel {{"version":99,"messages":[]}}
    close $channel
    set store [tConversationStore new $historyPath]
    try {
        set loadCode [catch {$store load} loadMessage]
        set channel [open $historyPath r]
        set remaining [read $channel]
        close $channel
        list $loadCode $loadMessage $remaining
    } finally {
        $store destroy
        file delete $historyPath
    }
} -result [list \
    1 "Unsupported conversation history version" \
    {{"version":99,"messages":[]}}]

test conversation-store-1.3 {summary metadata survives a JSON round trip} -body {
    set channel [file tempfile historyPath]
    close $channel
    set store [tConversationStore new $historyPath]
    set messages [list \
        [dict create role user content old] \
        [dict create role assistant content answer]]
    try {
        set state [dict create messages $messages \
            summary "Earlier summary" summarized_messages 2]
        $store saveState $state
        $store loadState
    } finally {
        $store destroy
        file delete $historyPath
    }
} -result [dict create messages [list \
    [dict create role user content old] \
    [dict create role assistant content answer]] \
    summary "Earlier summary" summarized_messages 2]

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
        return "sandboxed Tcl output"
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

test agent-smoke-1.1 {agent returns response and records conversation} -body {
    set client [::FakeLLMClient new]
    set agent [::tAgent new TestAgent "Test system role" $client]

    set response [$agent run "Test task"]
    set result [list $response [$agent getHistory] [$client getCalls]]

    $agent destroy
    $client destroy
    set result
} -result [list \
    "fake response" \
    [list \
        [dict create role user content "Test task"] \
        [dict create role assistant content "fake response"]] \
    [list [list "Test system role" [list \
        [dict create role user content "Test task"]]]]]

test agent-history-1.1 {second request contains the completed first turn} -body {
    set client [::FakeLLMClient new [list "first response" "second response"]]
    set agent [::tAgent new TestAgent "Test system role" $client]

    $agent run "first task"
    $agent run "second task"
    set result [list [$client getCalls] [$agent getHistory]]

    $agent destroy
    $client destroy
    set result
} -result [list \
    [list \
        [list "Test system role" [list \
            [dict create role user content "first task"]]] \
        [list "Test system role" [list \
            [dict create role user content "first task"] \
            [dict create role assistant content "first response"] \
            [dict create role user content "second task"]]]] \
    [list \
        [dict create role user content "first task"] \
        [dict create role assistant content "first response"] \
        [dict create role user content "second task"] \
        [dict create role assistant content "second response"]]]

test agent-history-1.2 {failed requests retain context for follow-ups} -body {
    set client [::FailingLLMClient new]
    set agent [::tAgent new TestAgent "Test system role" $client]

    set runResult [catch {$agent run "failed task"} runMessage]
    set result [list $runResult $runMessage [$agent getHistory]]

    $agent destroy
    $client destroy
    set result
} -result [list 1 "fake failure" [list \
    [dict create role user content "failed task"] \
    [dict create role assistant content \
        "The previous task ended before a final response: fake failure"]]]

test agent-history-1.3 {request context is bounded without trimming storage} -body {
    set client [::FakeLLMClient new [list \
        "one" "two" "three" "four"]]
    set agent [::tAgent new \
        TestAgent "Test system role" $client "" 8 "" 4]
    try {
        foreach task {first second third fourth} {
            $agent run $task
        }
        set fourthRequest [lindex [lindex [$client getCalls] 3] 1]
        list \
            [lmap message $fourthRequest {dict get $message content}] \
            [llength [$agent getHistory]]
    } finally {
        $agent destroy
        $client destroy
    }
} -result [list [list "second" "two" "third" "three" "fourth"] 8]

test agent-history-1.4 {an oversized tool turn is never split} -body {
    set client [::FakeLLMClient new [list "follow-up answer"]]
    set agent [::tAgent new \
        TestAgent "Test system role" $client "" 8 "" 2]
    set toolCall [dict create id call_1 type function function [dict create \
        name read_file arguments {{"path":"main.tcl"}}]]
    set history [list \
        [dict create role user content old] \
        [dict create role assistant content old-answer] \
        [dict create role user content inspect] \
        [dict create role assistant content "" tool_calls [list $toolCall]] \
        [dict create role tool content contents tool_call_id call_1] \
        [dict create role assistant content inspected]]
    try {
        $agent replaceHistory $history
        $agent run follow-up
        set request [lindex [lindex [$client getCalls] 0] 1]
        list \
            [lmap message $request {dict get $message role}] \
            [dict get [lindex $request 0] content] \
            [llength [$agent getHistory]]
    } finally {
        $agent destroy
        $client destroy
    }
} -result [list \
    [list user assistant tool assistant user] \
    inspect \
    8]

test agent-history-1.5 {excluded history and summary state are tracked} -body {
    set client [::FakeLLMClient new]
    set agent [::tAgent new \
        TestAgent "Test system role" $client "" 8 "" 4 true]
    set messages [list \
        [dict create role user content first] \
        [dict create role assistant content one] \
        [dict create role user content second] \
        [dict create role assistant content two] \
        [dict create role user content third] \
        [dict create role assistant content three]]
    try {
        $agent replaceHistoryState [dict create \
            messages $messages summary "First turn summary" \
            summarized_messages 2]
        list \
            [lmap message [$agent getExcludedHistory] {
                dict get $message content
            }] \
            [$agent getHistoryState] \
            [$agent summarizesHistory]
    } finally {
        $agent destroy
        $client destroy
    }
} -result [list \
    [list first one] \
    [dict create messages [list \
        [dict create role user content first] \
        [dict create role assistant content one] \
        [dict create role user content second] \
        [dict create role assistant content two] \
        [dict create role user content third] \
        [dict create role assistant content three]] \
        summary "First turn summary" summarized_messages 2] \
    1]

test startup-paths-1.1 {main loads outside the project directory} -body {
    set originalDirectory [pwd]
    set child [interp create]

    try {
        cd [file dirname $projectDir]
        $child eval [list source [file join $projectDir main.tcl]]
        $child eval {expr {
            [llength [info commands ::main]] == 1
            && [llength [info commands ::tAgent]] == 1
            && [llength [info commands ::tLLMClient]] == 1
        }}
    } finally {
        cd $originalDirectory
        interp delete $child
    }
} -result 1

test workspace-root-1.1 {workspace root supports relative and absolute paths} -body {
    set temporaryRoot [file join [temporaryDirectory] \
        "oodz-workspace-test-[pid]-[clock clicks]"]
    file mkdir [file join $temporaryRoot relative]
    try {
        set relative [::resolveWorkspaceRoot $temporaryRoot relative]
        set absolute [::resolveWorkspaceRoot \
            $projectDir [file join $temporaryRoot relative]]
        set missingCode [catch {
            ::resolveWorkspaceRoot $temporaryRoot missing
        } missingMessage]
        set emptyCode [catch {
            ::resolveWorkspaceRoot $temporaryRoot "  "
        } emptyMessage]
        list \
            [expr {$relative eq [file join $temporaryRoot relative]}] \
            [expr {$absolute eq $relative}] \
            $missingCode $missingMessage \
            $emptyCode $emptyMessage
    } finally {
        file delete -force $temporaryRoot
    }
} -result [list \
    1 1 \
    1 "Workspace.root is not a directory: missing" \
    1 "Workspace.root must not be empty"]

test plugin-directories-1.1 {personal plugin roots support relative and absolute paths} -body {
    set temporaryRoot [file join [temporaryDirectory] \
        "oodz-plugin-roots-test-[pid]-[clock clicks]"]
    set relativePath [file join $temporaryRoot personal]
    set absolutePath [file join [temporaryDirectory] \
        "oodz-absolute-plugins-test-[pid]-[clock clicks]"]
    file mkdir $relativePath $absolutePath
    try {
        set directories [::resolvePluginDirectories $temporaryRoot \
            "personal, $absolutePath, personal"]
        set missingCode [catch {
            ::resolvePluginDirectories $temporaryRoot missing
        } missingMessage]
        list \
            [llength $directories] \
            [expr {[lindex $directories 0] eq \
                [file join $temporaryRoot plugins]}] \
            [expr {[lindex $directories 1] eq $relativePath}] \
            [expr {[lindex $directories 2] eq $absolutePath}] \
            $missingCode $missingMessage
    } finally {
        file delete -force $temporaryRoot $absolutePath
    }
} -result [list \
    3 1 1 1 \
    1 "Plugin directory does not exist: missing"]

test workspace-instructions-1.1 {workspace instructions are confined bounded UTF-8} -body {
    set temporaryRoot [file join [temporaryDirectory] \
        "oodz-instructions-test-[pid]-[clock clicks]"]
    file mkdir [file join $temporaryRoot docs]
    set validPath [file join $temporaryRoot docs PROJECT.md]
    set validChannel [open $validPath wb]
    puts -nonewline $validChannel \
        [encoding convertto utf-8 "Use NX classes.\nPrefer ::oodz::baseObj."]
    close $validChannel
    set largePath [file join $temporaryRoot large.md]
    set largeChannel [open $largePath wb]
    puts -nonewline $largeChannel [string repeat x 17]
    close $largeChannel
    set invalidPath [file join $temporaryRoot invalid.md]
    set invalidChannel [open $invalidPath wb]
    puts -nonewline $invalidChannel [binary format H* ff]
    close $invalidChannel

    try {
        set loaded [::loadWorkspaceInstructions \
            $temporaryRoot docs/PROJECT.md]
        set disabled [::loadWorkspaceInstructions $temporaryRoot ""]
        set absoluteCode [catch {
            ::loadWorkspaceInstructions $temporaryRoot $validPath
        } absoluteMessage]
        set escapeCode [catch {
            ::loadWorkspaceInstructions $temporaryRoot ../outside.md
        } escapeMessage]
        set missingCode [catch {
            ::loadWorkspaceInstructions $temporaryRoot missing.md
        } missingMessage]
        set largeCode [catch {
            ::loadWorkspaceInstructions $temporaryRoot large.md 16
        } largeMessage]
        set invalidCode [catch {
            ::loadWorkspaceInstructions $temporaryRoot invalid.md
        } invalidMessage]
        list \
            $loaded $disabled \
            $absoluteCode $absoluteMessage \
            $escapeCode $escapeMessage \
            $missingCode $missingMessage \
            $largeCode $largeMessage \
            $invalidCode $invalidMessage
    } finally {
        file delete -force $temporaryRoot
    }
} -result [list \
    "Use NX classes.\nPrefer ::oodz::baseObj." "" \
    1 "Workspace.instructions must be relative to the workspace" \
    1 "Workspace instruction file escapes the workspace" \
    1 "Workspace instruction file does not exist: missing.md" \
    1 "Workspace instruction file exceeds 16 bytes: large.md" \
    1 "Workspace instruction file is not valid UTF-8: invalid.md"]

test workspace-confinement-1.1 {path confinement compares complete components} -body {
    set root [file normalize [file join [temporaryDirectory] workspace]]
    list \
        [::PluginSupport::isWithin $root $root] \
        [::PluginSupport::isWithin [file join $root modules tax] $root] \
        [::PluginSupport::isWithin "${root}-other" $root] \
        [::PluginSupport::isWithin [file dirname $root] $root]
} -result {1 1 0 0}

test hierarchical-instructions-1.1 {closest instruction files load in order} -body {
    set root [file normalize [file join \
        [::tcltest::temporaryDirectory] instructions-[pid]]]
    file mkdir [file join $root modules report nested]
    foreach {relative content} {
        AGENT.md {Root rules}
        modules/report/AGENT.md {Report rules}
        modules/report/nested/AGENT.md {Nested rules}
    } {
        set channel [open [file join $root $relative] w]
        fconfigure $channel -encoding utf-8
        puts $channel $content
        close $channel
    }
    set registry [::tInstructionRegistry new $root AGENT.md]
    try {
        set loaded [$registry loadForPath \
            modules/report/nested/new_file.tcl]
        set escapeCode [catch {
            $registry loadForPath ../outside.tcl
        } escapeMessage]
        list \
            [expr {[string first "## AGENT.md" $loaded] < 0}] \
            [expr {[string first "## modules/report/AGENT.md" $loaded] \
                < [string first \
                    "## modules/report/nested/AGENT.md" $loaded]}] \
            $escapeCode $escapeMessage
    } finally {
        $registry destroy
        file delete -force $root
    }
} -result [list 1 1 1 \
    "Instruction target path escapes the workspace"]

test hierarchical-instructions-1.2 {instruction tool is model-visible} -body {
    set root [file normalize [file join \
        [::tcltest::temporaryDirectory] instruction-tool-[pid]]]
    file mkdir [file join $root module]
    foreach {relative content} {
        AGENT.md {Root instructions}
        module/AGENT.md {Module instructions}
    } {
        set channel [open [file join $root $relative] w]
        puts $channel $content
        close $channel
    }
    set instructions [::tInstructionRegistry new $root AGENT.md]
    set plugins [::tPluginRegistry new \
        $root [list [file join $projectDir plugins]] \
        "" 1000 65536 {} "" $instructions]
    try {
        set loaded [$plugins invoke load_project_instructions \
            [::json::write object path \
                [::json::write string module/file.tcl]]]
        list \
            [expr {"load_project_instructions" in [$plugins names]}] \
            [expr {[string first "Module instructions" $loaded] >= 0}]
    } finally {
        $plugins destroy
        $instructions destroy
        file delete -force $root
    }
} -result [list 1 1]

test process-runner-1.1 {Tcl runner builds one confined command profile} -body {
    set root [file normalize [file join \
        [::tcltest::temporaryDirectory] process-runner-[pid]]]
    file mkdir $root
    set channel [open [file join $root hello.tcl] w]
    puts $channel {puts hello}
    close $channel
    set channel [open [file join $root hello.txt] w]
    puts $channel hello
    close $channel
    set ::RunnerMock::calls {}
    set runner [::tProcessRunner new \
        $root tclsh9.0 direct bwrap 2500 4096 ::RunnerMock::execute]
    set sandboxRunner [::tProcessRunner new \
        $root tclsh9.0 bubblewrap bwrap 2500 4096 ::RunnerMock::execute]
    try {
        set result [$runner runTclFile hello.tcl]
        set command [lindex [lindex $::RunnerMock::calls 0] 0]
        set sandboxCommand [$sandboxRunner buildTclCommand hello.tcl]
        $runner configureProjectTests \
            tclsh9.0 {tests/all.tcl -verbose body} 60000
        set projectResult [$runner runProjectTests]
        set projectCall [lindex $::RunnerMock::calls 1]
        set escapeCode [catch {
            $runner runTclFile ../outside.tcl
        } escapeMessage]
        set extensionCode [catch {
            $runner runTclFile hello.txt
        } extensionMessage]
        list \
            $result \
            [$runner mode] \
            [expr {"--unshare-all" ni $command}] \
            [expr {[lindex $command end] eq \
                [file join $root hello.tcl]}] \
            [expr {"--unshare-all" in $sandboxCommand}] \
            [expr {"/workspace/hello.tcl" in $sandboxCommand}] \
            [lindex [lindex $::RunnerMock::calls 0] 1] \
            [lindex [lindex $::RunnerMock::calls 0] 2] \
            $projectResult \
            [lrange [lindex $projectCall 0] 1 end] \
            [lindex $projectCall 1] \
            $escapeCode $escapeMessage \
            $extensionCode $extensionMessage
    } finally {
        $sandboxRunner destroy
        $runner destroy
        file delete -force $root
    }
} -result [list \
    "sandboxed Tcl output" direct 1 1 1 1 2500 4096 \
    "sandboxed Tcl output" {tests/all.tcl -verbose body} 60000 \
    1 "Plugin path escapes the workspace" \
    1 "Tcl runner accepts only .tcl files"]

test process-runner-1.1a {configured executable alias controls plugin commands} -body {
    set root [file normalize [file join \
        [::tcltest::temporaryDirectory] executable-alias-[pid]]]
    file mkdir $root
    set ::RunnerMock::calls {}
    set configuredPath [file normalize [info nameofexecutable]]
    set runner [::tProcessRunner new \
        $root tclsh9.0 direct bwrap 2500 4096 \
        ::RunnerMock::execute [dict create fossil $configuredPath]]
    try {
        set result [$runner runConfiguredCommand fossil [list version]]
        set call [lindex $::RunnerMock::calls 0]
        list \
            $result \
            [expr {[lindex [lindex $call 0] 0] eq $configuredPath}] \
            [lrange [lindex $call 0] 1 end]
    } finally {
        $runner destroy
        file delete -force $root
    }
} -result [list "sandboxed Tcl output" 1 [list version]]

test process-runner-1.2 {Tcl execution is model-visible and approved} -body {
    set root [file normalize [file join \
        [::tcltest::temporaryDirectory] process-tool-[pid]]]
    file mkdir $root
    set channel [open [file join $root hello.tcl] w]
    puts $channel {puts hello}
    close $channel
    set runner [::tProcessRunner new \
        $root tclsh9.0 direct bwrap 2500 4096 ::RunnerMock::execute]
    $runner configureProjectTests tclsh9.0 tests/all.tcl 60000
    set plugins [::tPluginRegistry new \
        $root [list [file join $projectDir plugins]] \
        ::ApprovalMock::decide 1000 65536 {} "" "" $runner]
    set config [::FakeConfig new [dict create LLM.api_key test-only-key]]
    set client [::tLLMClient new $config]
    set arguments [::json::write object path \
        [::json::write string hello.tcl]]
    try {
        set ::ApprovalMock::approved 0
        set deniedCode [catch {
            $plugins invoke run_tcl_file $arguments
        } deniedMessage]
        set ::ApprovalMock::approved 1
        set result [$plugins invoke run_tcl_file $arguments]
        set projectResult [$plugins invoke run_project_tests \
            [::json::write object]]
        set payload [::json::json2dict [$client buildPayload \
            system [list [dict create role user content test]] \
            [$plugins definitions]]]
        set parameterType ""
        foreach definition [dict get $payload tools] {
            if {[dict get $definition function name] eq "run_tcl_file"} {
                set parameterType \
                    [dict get $definition function parameters type]
            }
        }
        list \
            [expr {"run_tcl_file" in [$plugins names]}] \
            [expr {"run_project_tests" in [$plugins names]}] \
            $deniedCode $deniedMessage $result $projectResult $parameterType
    } finally {
        $client destroy
        $config destroy
        $plugins destroy
        $runner destroy
        file delete -force $root
    }
} -result [list \
    1 1 1 "Plugin execution denied: run_tcl_file" \
    "sandboxed Tcl output" "sandboxed Tcl output" object]

test fossil-status-1.1 {Fossil status uses one fixed bounded command} -body {
    set root [file normalize [file join \
        [::tcltest::temporaryDirectory] fossil-status-[pid]]]
    file mkdir $root
    set ::RunnerMock::calls {}
    set runner [::tProcessRunner new \
        $root tclsh9.0 direct bwrap 2500 4096 ::RunnerMock::execute]
    set plugins [::tPluginRegistry new \
        $root [list [file join $projectDir plugins]] \
        "" 1000 65536 {} "" "" $runner]
    try {
        set result [$plugins invoke fossil_status \
            [::json::write object]]
        set call [lindex $::RunnerMock::calls 0]
        set command [lindex $call 0]
        set fossilDefinition {}
        foreach definition [$plugins definitions] {
            if {[dict get $definition name] eq "fossil_status"} {
                set fossilDefinition $definition
                break
            }
        }
        list \
            $result \
            [file tail [lindex $command 0]] \
            [lrange $command 1 end] \
            [lindex $call 1] \
            [lindex $call 2] \
            [dict get $fossilDefinition parameters properties] \
            [dict get $fossilDefinition parameters required]
    } finally {
        $plugins destroy
        $runner destroy
        file delete -force $root
    }
} -result [list \
    "sandboxed Tcl output" fossil [list status] 2500 4096 \
    [dict create] [list]]

test fossil-changes-1.1 {Fossil changes is concise and fixed} -body {
    set root [file normalize [file join \
        [::tcltest::temporaryDirectory] fossil-changes-[pid]]]
    file mkdir $root
    set ::RunnerMock::calls {}
    set runner [::tProcessRunner new \
        $root tclsh9.0 direct bwrap 2500 4096 ::RunnerMock::execute]
    set plugins [::tPluginRegistry new \
        $root [list [file join $projectDir plugins]] \
        "" 1000 65536 {} "" "" $runner]
    try {
        set result [$plugins invoke fossil_changes \
            [::json::write object]]
        set call [lindex $::RunnerMock::calls 0]
        list $result [lrange [lindex $call 0] 1 end]
    } finally {
        $plugins destroy
        $runner destroy
        file delete -force $root
    }
} -result [list "sandboxed Tcl output" \
    [list changes --classify --no-merge --rel-paths --verbose]]

test fossil-branches-1.1 {Fossil branches lists all branches} -body {
    set root [file normalize [file join \
        [::tcltest::temporaryDirectory] fossil-branches-[pid]]]
    file mkdir $root
    set ::RunnerMock::calls {}
    set runner [::tProcessRunner new \
        $root tclsh9.0 direct bwrap 2500 4096 ::RunnerMock::execute]
    set plugins [::tPluginRegistry new \
        $root [list [file join $projectDir plugins]] \
        "" 1000 65536 {} "" "" $runner]
    try {
        set result [$plugins invoke fossil_branches [::json::write object]]
        set call [lindex $::RunnerMock::calls 0]
        list $result [lrange [lindex $call 0] 1 end]
    } finally {
        $plugins destroy
        $runner destroy
        file delete -force $root
    }
} -result [list "sandboxed Tcl output" [list branch list --all]]

test fossil-branch-info-1.1 {Fossil branch info is bounded and fixed} -body {
    set root [file normalize [file join \
        [::tcltest::temporaryDirectory] fossil-branch-info-[pid]]]
    file mkdir $root
    set ::RunnerMock::calls {}
    set runner [::tProcessRunner new \
        $root tclsh9.0 direct bwrap 2500 4096 ::RunnerMock::execute]
    set plugins [::tPluginRegistry new \
        $root [list [file join $projectDir plugins]] \
        "" 1000 65536 {} "" "" $runner]
    try {
        set result [$plugins invoke fossil_branch_info \
            [::json::write object name [::json::write string "release/v2"]]]
        set call [lindex $::RunnerMock::calls 0]
        set emptyCode [catch {
            $plugins invoke fossil_branch_info [::json::write object \
                name [::json::write string "  "]]
        } emptyMessage]
        list $result [lrange [lindex $call 0] 1 end] \
            $emptyCode $emptyMessage
    } finally {
        $plugins destroy
        $runner destroy
        file delete -force $root
    }
} -result [list "sandboxed Tcl output" \
    [list branch info -- release/v2] \
    1 "fossil_branch_info name must not be empty"]

test fossil-branch-close-1.1 {Fossil branch close is approved and local} -body {
    set root [file normalize [file join \
        [::tcltest::temporaryDirectory] fossil-branch-close-[pid]]]
    file mkdir $root
    set ::RunnerMock::calls {}
    set runner [::tProcessRunner new \
        $root tclsh9.0 direct bwrap 2500 4096 ::RunnerMock::execute]
    set plugins [::tPluginRegistry new \
        $root [list [file join $projectDir plugins]] \
        ::ApprovalMock::decide 1000 65536 {} "" "" $runner]
    set arguments [::json::write object \
        name [::json::write string feature/accounts]]
    try {
        set ::ApprovalMock::approved 0
        set deniedCode [catch {
            $plugins invoke fossil_branch_close $arguments
        } deniedMessage]
        set ::ApprovalMock::approved 1
        set result [$plugins invoke fossil_branch_close $arguments]
        set call [lindex $::RunnerMock::calls 0]
        list $deniedCode $deniedMessage $result \
            [lrange [lindex $call 0] 1 end]
    } finally {
        $plugins destroy
        $runner destroy
        file delete -force $root
    }
} -result [list \
    1 "Plugin execution denied: fossil_branch_close" \
    "sandboxed Tcl output" \
    [list branch close --nosync -- feature/accounts]]

test fossil-branch-reopen-1.1 {Fossil branch reopen is approved and local} -body {
    set root [file normalize [file join \
        [::tcltest::temporaryDirectory] fossil-branch-reopen-[pid]]]
    file mkdir $root
    set ::RunnerMock::calls {}
    set runner [::tProcessRunner new \
        $root tclsh9.0 direct bwrap 2500 4096 ::RunnerMock::execute]
    set plugins [::tPluginRegistry new \
        $root [list [file join $projectDir plugins]] \
        ::ApprovalMock::decide 1000 65536 {} "" "" $runner]
    set arguments [::json::write object \
        name [::json::write string feature/accounts]]
    try {
        set ::ApprovalMock::approved 0
        set deniedCode [catch {
            $plugins invoke fossil_branch_reopen $arguments
        } deniedMessage]
        set ::ApprovalMock::approved 1
        set result [$plugins invoke fossil_branch_reopen $arguments]
        set call [lindex $::RunnerMock::calls 0]
        list $deniedCode $deniedMessage $result \
            [lrange [lindex $call 0] 1 end]
    } finally {
        $plugins destroy
        $runner destroy
        file delete -force $root
    }
} -result [list \
    1 "Plugin execution denied: fossil_branch_reopen" \
    "sandboxed Tcl output" \
    [list branch reopen --nosync -- feature/accounts]]

test fossil-branch-new-1.1 {Fossil branch creation is approved and local} -body {
    set root [file normalize [file join \
        [::tcltest::temporaryDirectory] fossil-branch-new-[pid]]]
    file mkdir $root
    set ::RunnerMock::calls {}
    set runner [::tProcessRunner new \
        $root tclsh9.0 direct bwrap 2500 4096 ::RunnerMock::execute]
    set plugins [::tPluginRegistry new \
        $root [list [file join $projectDir plugins]] \
        ::ApprovalMock::decide 1000 65536 {} "" "" $runner]
    set arguments [::json::write object \
        name [::json::write string feature/accounts] \
        basis [::json::write string trunk]]
    try {
        set ::ApprovalMock::approved 0
        set deniedCode [catch {
            $plugins invoke fossil_branch_new $arguments
        } deniedMessage]
        set ::ApprovalMock::approved 1
        set result [$plugins invoke fossil_branch_new $arguments]
        set call [lindex $::RunnerMock::calls 0]
        list $deniedCode $deniedMessage $result \
            [lrange [lindex $call 0] 1 end]
    } finally {
        $plugins destroy
        $runner destroy
        file delete -force $root
    }
} -result [list \
    1 "Plugin execution denied: fossil_branch_new" \
    "sandboxed Tcl output" \
    [list branch new --nosync -- feature/accounts trunk]]

test fossil-branch-switch-1.1 {Fossil branch switching is approved and local} -body {
    set root [file normalize [file join \
        [::tcltest::temporaryDirectory] fossil-branch-switch-[pid]]]
    file mkdir $root
    set ::RunnerMock::calls {}
    set runner [::tProcessRunner new \
        $root tclsh9.0 direct bwrap 2500 4096 ::RunnerMock::execute]
    set plugins [::tPluginRegistry new \
        $root [list [file join $projectDir plugins]] \
        ::ApprovalMock::decide 1000 65536 {} "" "" $runner]
    set arguments [::json::write object \
        name [::json::write string feature/accounts]]
    try {
        set ::ApprovalMock::approved 0
        set deniedCode [catch {
            $plugins invoke fossil_branch_switch $arguments
        } deniedMessage]
        set ::ApprovalMock::approved 1
        set result [$plugins invoke fossil_branch_switch $arguments]
        set call [lindex $::RunnerMock::calls 0]
        list $deniedCode $deniedMessage $result \
            [lrange [lindex $call 0] 1 end]
    } finally {
        $plugins destroy
        $runner destroy
        file delete -force $root
    }
} -result [list \
    1 "Plugin execution denied: fossil_branch_switch" \
    "sandboxed Tcl output" \
    [list update --nosync -- feature/accounts]]

test fossil-integration-1.1 {Fossil plugins operate on a real checkout} \
        -constraints fossilAvailable -body {
    set base [file normalize [file join \
        [::tcltest::temporaryDirectory] fossil-integration-[pid]]]
    set root [file join $base checkout]
    set repository [file join $base integration.fossil]
    file delete -force $base
    file mkdir $root
    set hadXdgConfigHome [info exists ::env(XDG_CONFIG_HOME)]
    if {$hadXdgConfigHome} {
        set previousXdgConfigHome $::env(XDG_CONFIG_HOME)
    }
    set ::env(XDG_CONFIG_HOME) [file join $base config]
    file mkdir $::env(XDG_CONFIG_HOME)
    exec fossil init $repository 2>@1
    set previousDirectory [pwd]
    try {
        cd $root
        exec fossil open $repository 2>@1
    } finally {
        cd $previousDirectory
    }
    set channel [open [file join $root hello.tcl] w]
    puts $channel {puts "real Fossil integration"}
    close $channel

    set runner [::tProcessRunner new \
        $root tclsh9.0 direct bwrap 10000 65536]
    set plugins [::tPluginRegistry new \
        $root [list [file join $projectDir plugins]] \
        ::ApprovalMock::decide 1000 65536 {} "" "" $runner]
    try {
        set ::ApprovalMock::approved 1
        set extras [$plugins invoke fossil_extras [::json::write object]]
        $plugins invoke fossil_add [::json::write object \
            path [::json::write string hello.tcl]]
        set changes [$plugins invoke fossil_changes [::json::write object]]
        $plugins invoke fossil_commit [::json::write object \
            message [::json::write string \
                "Exercise the real Fossil plugin workflow"]]
        set cleanChanges \
            [$plugins invoke fossil_changes [::json::write object]]
        set channel [open [file join $root hello.tcl] a]
        puts $channel {puts "stashed change"}
        close $channel
        $plugins invoke fossil_stash_save [::json::write object \
            comment [::json::write string "Integration test stash"]]
        set stashList [$plugins invoke fossil_stash_list \
            [::json::write object]]
        set stashedChanges \
            [$plugins invoke fossil_changes [::json::write object]]
        $plugins invoke fossil_stash_pop [::json::write object]
        set poppedChanges \
            [$plugins invoke fossil_changes [::json::write object]]
        $plugins invoke fossil_revert [::json::write object \
            path [::json::write string hello.tcl]]
        $plugins invoke fossil_branch_new [::json::write object \
            name [::json::write string integration-test] \
            basis [::json::write string trunk]]
        set branchInfo [$plugins invoke fossil_branch_info \
            [::json::write object \
                name [::json::write string integration-test]]]
        $plugins invoke fossil_branch_switch [::json::write object \
            name [::json::write string integration-test]]
        set status [$plugins invoke fossil_status [::json::write object]]
        $plugins invoke fossil_branch_close [::json::write object \
            name [::json::write string integration-test]]
        $plugins invoke fossil_branch_reopen [::json::write object \
            name [::json::write string integration-test]]
        set channel [open [file join $root hello.tcl] a]
        puts $channel {puts "branch-only change"}
        close $channel
        $plugins invoke fossil_commit [::json::write object \
            message [::json::write string \
                "Add a branch-only integration change"]]
        $plugins invoke fossil_branch_switch [::json::write object \
            name [::json::write string trunk]]
        $plugins invoke fossil_merge [::json::write object \
            source [::json::write string integration-test]]
        set mergedChanges \
            [$plugins invoke fossil_changes [::json::write object]]
        list \
            [expr {[string first "hello.tcl" $extras] >= 0}] \
            [expr {[string first "hello.tcl" $changes] >= 0}] \
            [expr {[string trim $cleanChanges] eq "(none)"}] \
            [expr {[string first "Integration test stash" $stashList] >= 0}] \
            [expr {[string trim $stashedChanges] eq "(none)"}] \
            [expr {[string first "hello.tcl" $poppedChanges] >= 0}] \
            [expr {[string first "integration-test" $branchInfo] >= 0}] \
            [expr {[string first "integration-test" $status] >= 0}] \
            [expr {[string first "hello.tcl" $mergedChanges] >= 0}]
    } finally {
        $plugins destroy
        $runner destroy
        if {$hadXdgConfigHome} {
            set ::env(XDG_CONFIG_HOME) $previousXdgConfigHome
        } else {
            unset ::env(XDG_CONFIG_HOME)
        }
        file delete -force $base
    }
} -result [list 1 1 1 1 1 1 1 1 1]

test fossil-extras-1.1 {Fossil extras is relative and fixed} -body {
    set root [file normalize [file join \
        [::tcltest::temporaryDirectory] fossil-extras-[pid]]]
    file mkdir $root
    set ::RunnerMock::calls {}
    set runner [::tProcessRunner new \
        $root tclsh9.0 direct bwrap 2500 4096 ::RunnerMock::execute]
    set plugins [::tPluginRegistry new \
        $root [list [file join $projectDir plugins]] \
        "" 1000 65536 {} "" "" $runner]
    try {
        set result [$plugins invoke fossil_extras \
            [::json::write object]]
        set call [lindex $::RunnerMock::calls 0]
        list $result [lrange [lindex $call 0] 1 end]
    } finally {
        $plugins destroy
        $runner destroy
        file delete -force $root
    }
} -result [list "sandboxed Tcl output" [list extras --rel-paths]]

test fossil-ls-1.1 {Fossil ls reports every managed file with status} -body {
    set root [file normalize [file join \
        [::tcltest::temporaryDirectory] fossil-ls-[pid]]]
    file mkdir $root
    set ::RunnerMock::calls {}
    set runner [::tProcessRunner new \
        $root tclsh9.0 direct bwrap 2500 4096 ::RunnerMock::execute]
    set plugins [::tPluginRegistry new \
        $root [list [file join $projectDir plugins]] \
        "" 1000 65536 {} "" "" $runner]
    try {
        set result [$plugins invoke fossil_ls [::json::write object]]
        set call [lindex $::RunnerMock::calls 0]
        list $result [lrange [lindex $call 0] 1 end]
    } finally {
        $plugins destroy
        $runner destroy
        file delete -force $root
    }
} -result [list "sandboxed Tcl output" [list ls --verbose]]

test fossil-info-1.1 {Fossil info uses one fixed bounded command} -body {
    set root [file normalize [file join \
        [::tcltest::temporaryDirectory] fossil-info-[pid]]]
    file mkdir $root
    set ::RunnerMock::calls {}
    set runner [::tProcessRunner new \
        $root tclsh9.0 direct bwrap 2500 4096 ::RunnerMock::execute]
    set plugins [::tPluginRegistry new \
        $root [list [file join $projectDir plugins]] \
        "" 1000 65536 {} "" "" $runner]
    try {
        set result [$plugins invoke fossil_info \
            [::json::write object]]
        set call [lindex $::RunnerMock::calls 0]
        list \
            $result \
            [file tail [lindex [lindex $call 0] 0]] \
            [lrange [lindex $call 0] 1 end] \
            [lindex $call 1] [lindex $call 2]
    } finally {
        $plugins destroy
        $runner destroy
        file delete -force $root
    }
} -result [list \
    "sandboxed Tcl output" fossil [list info] 2500 4096]

test fossil-pull-1.1 {Fossil pull uses only the configured remote} -body {
    set root [file normalize [file join \
        [::tcltest::temporaryDirectory] fossil-pull-[pid]]]
    file mkdir $root
    set ::RunnerMock::calls {}
    set runner [::tProcessRunner new \
        $root tclsh9.0 direct bwrap 2500 4096 ::RunnerMock::execute]
    set plugins [::tPluginRegistry new \
        $root [list [file join $projectDir plugins]] \
        ::ApprovalMock::decide 1000 65536 {} "" "" $runner]
    try {
        set ::ApprovalMock::approved 0
        set deniedCode [catch {
            $plugins invoke fossil_pull [::json::write object]
        } deniedMessage]
        set ::ApprovalMock::approved 1
        set result [$plugins invoke fossil_pull [::json::write object]]
        set call [lindex $::RunnerMock::calls 0]
        list $deniedCode $deniedMessage $result \
            [lrange [lindex $call 0] 1 end]
    } finally {
        $plugins destroy
        $runner destroy
        file delete -force $root
    }
} -result [list \
    1 "Plugin execution denied: fossil_pull" \
    "sandboxed Tcl output" [list pull]]

test fossil-merge-1.1 {Fossil merge is one-source approved and local} -body {
    set root [file normalize [file join \
        [::tcltest::temporaryDirectory] fossil-merge-[pid]]]
    file mkdir $root
    set ::RunnerMock::calls {}
    set runner [::tProcessRunner new \
        $root tclsh9.0 direct bwrap 2500 4096 ::RunnerMock::execute]
    set plugins [::tPluginRegistry new \
        $root [list [file join $projectDir plugins]] \
        ::ApprovalMock::decide 1000 65536 {} "" "" $runner]
    set arguments [::json::write object source \
        [::json::write string feature/accounts]]
    try {
        set ::ApprovalMock::approved 0
        set deniedCode [catch {
            $plugins invoke fossil_merge $arguments
        } deniedMessage]
        set ::ApprovalMock::approved 1
        set result [$plugins invoke fossil_merge $arguments]
        set call [lindex $::RunnerMock::calls 0]
        set emptyCode [catch {
            $plugins invoke fossil_merge [::json::write object source \
                [::json::write string "  "]]
        } emptyMessage]
        list $deniedCode $deniedMessage $result \
            [lrange [lindex $call 0] 1 end] $emptyCode $emptyMessage
    } finally {
        $plugins destroy
        $runner destroy
        file delete -force $root
    }
} -result [list \
    1 "Plugin execution denied: fossil_merge" \
    "sandboxed Tcl output" \
    [list merge --nosync -- feature/accounts] \
    1 "fossil_merge source must not be empty"]

test fossil-push-1.1 {Fossil push uses only the configured remote} -body {
    set root [file normalize [file join \
        [::tcltest::temporaryDirectory] fossil-push-[pid]]]
    file mkdir $root
    set ::RunnerMock::calls {}
    set runner [::tProcessRunner new \
        $root tclsh9.0 direct bwrap 2500 4096 ::RunnerMock::execute]
    set plugins [::tPluginRegistry new \
        $root [list [file join $projectDir plugins]] \
        ::ApprovalMock::decide 1000 65536 {} "" "" $runner]
    try {
        set ::ApprovalMock::approved 0
        set deniedCode [catch {
            $plugins invoke fossil_push [::json::write object]
        } deniedMessage]
        set ::ApprovalMock::approved 1
        set result [$plugins invoke fossil_push [::json::write object]]
        set call [lindex $::RunnerMock::calls 0]
        list $deniedCode $deniedMessage $result \
            [lrange [lindex $call 0] 1 end]
    } finally {
        $plugins destroy
        $runner destroy
        file delete -force $root
    }
} -result [list \
    1 "Plugin execution denied: fossil_push" \
    "sandboxed Tcl output" [list push]]

test fossil-stash-1.1 {Fossil stash tools are bounded and approved} -body {
    set root [file normalize [file join \
        [::tcltest::temporaryDirectory] fossil-stash-[pid]]]
    file mkdir $root
    set ::RunnerMock::calls {}
    set runner [::tProcessRunner new \
        $root tclsh9.0 direct bwrap 2500 4096 ::RunnerMock::execute]
    set plugins [::tPluginRegistry new \
        $root [list [file join $projectDir plugins]] \
        ::ApprovalMock::decide 1000 65536 {} "" "" $runner]
    set saveArguments [::json::write object comment \
        [::json::write string "Pause account form work"]]
    try {
        set listResult [$plugins invoke fossil_stash_list \
            [::json::write object]]
        set ::ApprovalMock::approved 0
        set deniedCode [catch {
            $plugins invoke fossil_stash_save $saveArguments
        } deniedMessage]
        set ::ApprovalMock::approved 1
        set saveResult [$plugins invoke fossil_stash_save $saveArguments]
        set popResult [$plugins invoke fossil_stash_pop \
            [::json::write object]]
        set emptyCode [catch {
            $plugins invoke fossil_stash_save [::json::write object \
                comment [::json::write string "  "]]
        } emptyMessage]
        list $listResult $deniedCode $deniedMessage \
            $saveResult $popResult \
            [lrange [lindex [lindex $::RunnerMock::calls 0] 0] 1 end] \
            [lrange [lindex [lindex $::RunnerMock::calls 1] 0] 1 end] \
            [lrange [lindex [lindex $::RunnerMock::calls 2] 0] 1 end] \
            $emptyCode $emptyMessage
    } finally {
        $plugins destroy
        $runner destroy
        file delete -force $root
    }
} -result [list \
    "sandboxed Tcl output" \
    1 "Plugin execution denied: fossil_stash_save" \
    "sandboxed Tcl output" "sandboxed Tcl output" \
    [list stash list --verbose] \
    [list stash save --comment "Pause account form work"] \
    [list stash pop] \
    1 "fossil_stash_save comment must not be empty"]

test fossil-add-1.1 {Fossil add is approved and file-confined} -body {
    set root [file normalize [file join \
        [::tcltest::temporaryDirectory] fossil-add-[pid]]]
    file mkdir [file join $root src]
    set channel [open [file join $root src new.tcl] w]
    puts $channel {puts new}
    close $channel
    set ::RunnerMock::calls {}
    set runner [::tProcessRunner new \
        $root tclsh9.0 direct bwrap 2500 4096 ::RunnerMock::execute]
    set plugins [::tPluginRegistry new \
        $root [list [file join $projectDir plugins]] \
        ::ApprovalMock::decide 1000 65536 {} "" "" $runner]
    set arguments [::json::write object path \
        [::json::write string src/new.tcl]]
    try {
        set ::ApprovalMock::approved 0
        set deniedCode [catch {
            $plugins invoke fossil_add $arguments
        } deniedMessage]
        set ::ApprovalMock::approved 1
        set result [$plugins invoke fossil_add $arguments]
        set directoryCode [catch {
            $plugins invoke fossil_add [::json::write object path \
                [::json::write string src]]
        } directoryMessage]
        set escapeCode [catch {
            $plugins invoke fossil_add [::json::write object path \
                [::json::write string ../outside.tcl]]
        } escapeMessage]
        list \
            $deniedCode $deniedMessage \
            $result \
            [lrange [lindex [lindex $::RunnerMock::calls 0] 0] 1 end] \
            $directoryCode $directoryMessage \
            $escapeCode $escapeMessage
    } finally {
        $plugins destroy
        $runner destroy
        file delete -force $root
    }
} -result [list \
    1 "Plugin execution denied: fossil_add" \
    "sandboxed Tcl output" [list add -- src/new.tcl] \
    1 "fossil_add path is not an existing file: src" \
    1 "Plugin path escapes the workspace"]

test fossil-commit-1.1 {Fossil commit is approved local and bounded} -body {
    set root [file normalize [file join \
        [::tcltest::temporaryDirectory] fossil-commit-[pid]]]
    file mkdir $root
    set ::RunnerMock::calls {}
    set runner [::tProcessRunner new \
        $root tclsh9.0 direct bwrap 2500 4096 ::RunnerMock::execute]
    set plugins [::tPluginRegistry new \
        $root [list [file join $projectDir plugins]] \
        ::ApprovalMock::decide 1000 65536 {} "" "" $runner]
    set arguments [::json::write object message \
        [::json::write string "Add account class safely"]]
    try {
        set ::ApprovalMock::approved 0
        set deniedCode [catch {
            $plugins invoke fossil_commit $arguments
        } deniedMessage]
        set ::ApprovalMock::approved 1
        set result [$plugins invoke fossil_commit $arguments]
        set emptyCode [catch {
            $plugins invoke fossil_commit [::json::write object message \
                [::json::write string "   "]]
        } emptyMessage]
        set longCode [catch {
            $plugins invoke fossil_commit [::json::write object message \
                [::json::write string [string repeat x 1001]]]
        } longMessage]
        list \
            $deniedCode $deniedMessage \
            $result \
            [lrange [lindex [lindex $::RunnerMock::calls 0] 0] 1 end] \
            $emptyCode $emptyMessage $longCode $longMessage
    } finally {
        $plugins destroy
        $runner destroy
        file delete -force $root
    }
} -result [list \
    1 "Plugin execution denied: fossil_commit" \
    "sandboxed Tcl output" \
    [list commit --nosync --no-prompt -m "Add account class safely"] \
    1 "fossil_commit message must not be empty" \
    1 "fossil_commit message exceeds configured limit: 1000"]

test fossil-revert-1.1 {Fossil revert is approved and file-confined} -body {
    set root [file normalize [file join \
        [::tcltest::temporaryDirectory] fossil-revert-[pid]]]
    file mkdir [file join $root src]
    set channel [open [file join $root src client.tcl] w]
    puts $channel {puts changed}
    close $channel
    set ::RunnerMock::calls {}
    set runner [::tProcessRunner new \
        $root tclsh9.0 direct bwrap 2500 4096 ::RunnerMock::execute]
    set plugins [::tPluginRegistry new \
        $root [list [file join $projectDir plugins]] \
        ::ApprovalMock::decide 1000 65536 {} "" "" $runner]
    set arguments [::json::write object path \
        [::json::write string src/client.tcl]]
    try {
        set ::ApprovalMock::approved 0
        set deniedCode [catch {
            $plugins invoke fossil_revert $arguments
        } deniedMessage]
        set ::ApprovalMock::approved 1
        set result [$plugins invoke fossil_revert $arguments]
        set directoryCode [catch {
            $plugins invoke fossil_revert [::json::write object path \
                [::json::write string src]]
        } directoryMessage]
        set escapeCode [catch {
            $plugins invoke fossil_revert [::json::write object path \
                [::json::write string ../outside.tcl]]
        } escapeMessage]
        list \
            $deniedCode $deniedMessage \
            $result \
            [lrange [lindex [lindex $::RunnerMock::calls 0] 0] 1 end] \
            $directoryCode $directoryMessage \
            $escapeCode $escapeMessage
    } finally {
        $plugins destroy
        $runner destroy
        file delete -force $root
    }
} -result [list \
    1 "Plugin execution denied: fossil_revert" \
    "sandboxed Tcl output" [list revert -- src/client.tcl] \
    1 "fossil_revert path is not an existing file: src" \
    1 "Plugin path escapes the workspace"]

test fossil-update-1.1 {Fossil update is approved fixed and local} -body {
    set root [file normalize [file join \
        [::tcltest::temporaryDirectory] fossil-update-[pid]]]
    file mkdir $root
    set ::RunnerMock::calls {}
    set runner [::tProcessRunner new \
        $root tclsh9.0 direct bwrap 2500 4096 ::RunnerMock::execute]
    set plugins [::tPluginRegistry new \
        $root [list [file join $projectDir plugins]] \
        ::ApprovalMock::decide 1000 65536 {} "" "" $runner]
    set arguments [::json::write object]
    try {
        set ::ApprovalMock::approved 0
        set deniedCode [catch {
            $plugins invoke fossil_update $arguments
        } deniedMessage]
        set ::ApprovalMock::approved 1
        set result [$plugins invoke fossil_update $arguments]
        set call [lindex $::RunnerMock::calls 0]
        list \
            $deniedCode $deniedMessage $result \
            [file tail [lindex [lindex $call 0] 0]] \
            [lrange [lindex $call 0] 1 end] \
            [lindex $call 1] [lindex $call 2]
    } finally {
        $plugins destroy
        $runner destroy
        file delete -force $root
    }
} -result [list \
    1 "Plugin execution denied: fossil_update" \
    "sandboxed Tcl output" fossil [list update --nosync] 2500 4096]

test fossil-undo-1.1 {Fossil undo is approved and path-confined} -body {
    set root [file normalize [file join \
        [::tcltest::temporaryDirectory] fossil-undo-[pid]]]
    file mkdir [file join $root src]
    set ::RunnerMock::calls {}
    set runner [::tProcessRunner new \
        $root tclsh9.0 direct bwrap 2500 4096 ::RunnerMock::execute]
    set plugins [::tPluginRegistry new \
        $root [list [file join $projectDir plugins]] \
        ::ApprovalMock::decide 1000 65536 {} "" "" $runner]
    set arguments [::json::write object path \
        [::json::write string src/deleted.tcl]]
    try {
        set ::ApprovalMock::approved 0
        set deniedCode [catch {
            $plugins invoke fossil_undo $arguments
        } deniedMessage]
        set ::ApprovalMock::approved 1
        set result [$plugins invoke fossil_undo $arguments]
        set escapeCode [catch {
            $plugins invoke fossil_undo [::json::write object path \
                [::json::write string ../outside.tcl]]
        } escapeMessage]
        list \
            $deniedCode $deniedMessage $result \
            [lrange [lindex [lindex $::RunnerMock::calls 0] 0] 1 end] \
            $escapeCode $escapeMessage
    } finally {
        $plugins destroy
        $runner destroy
        file delete -force $root
    }
} -result [list \
    1 "Plugin execution denied: fossil_undo" \
    "sandboxed Tcl output" [list undo -- src/deleted.tcl] \
    1 "Plugin path escapes the workspace"]

test fossil-redo-1.1 {Fossil redo is approved and path-confined} -body {
    set root [file normalize [file join \
        [::tcltest::temporaryDirectory] fossil-redo-[pid]]]
    file mkdir [file join $root src]
    set ::RunnerMock::calls {}
    set runner [::tProcessRunner new \
        $root tclsh9.0 direct bwrap 2500 4096 ::RunnerMock::execute]
    set plugins [::tPluginRegistry new \
        $root [list [file join $projectDir plugins]] \
        ::ApprovalMock::decide 1000 65536 {} "" "" $runner]
    set arguments [::json::write object path \
        [::json::write string src/deleted.tcl]]
    try {
        set ::ApprovalMock::approved 0
        set deniedCode [catch {
            $plugins invoke fossil_redo $arguments
        } deniedMessage]
        set ::ApprovalMock::approved 1
        set result [$plugins invoke fossil_redo $arguments]
        set escapeCode [catch {
            $plugins invoke fossil_redo [::json::write object path \
                [::json::write string ../outside.tcl]]
        } escapeMessage]
        list \
            $deniedCode $deniedMessage $result \
            [lrange [lindex [lindex $::RunnerMock::calls 0] 0] 1 end] \
            $escapeCode $escapeMessage
    } finally {
        $plugins destroy
        $runner destroy
        file delete -force $root
    }
} -result [list \
    1 "Plugin execution denied: fossil_redo" \
    "sandboxed Tcl output" [list redo -- src/deleted.tcl] \
    1 "Plugin path escapes the workspace"]

test fossil-remove-1.1 {Fossil remove is approved hard and file-confined} -body {
    set root [file normalize [file join \
        [::tcltest::temporaryDirectory] fossil-remove-[pid]]]
    file mkdir [file join $root src]
    set channel [open [file join $root src obsolete.tcl] w]
    puts $channel {puts obsolete}
    close $channel
    set ::RunnerMock::calls {}
    set runner [::tProcessRunner new \
        $root tclsh9.0 direct bwrap 2500 4096 ::RunnerMock::execute]
    set plugins [::tPluginRegistry new \
        $root [list [file join $projectDir plugins]] \
        ::ApprovalMock::decide 1000 65536 {} "" "" $runner]
    set arguments [::json::write object path \
        [::json::write string src/obsolete.tcl]]
    try {
        set ::ApprovalMock::approved 0
        set deniedCode [catch {
            $plugins invoke fossil_remove $arguments
        } deniedMessage]
        set ::ApprovalMock::approved 1
        set result [$plugins invoke fossil_remove $arguments]
        set directoryCode [catch {
            $plugins invoke fossil_remove [::json::write object path \
                [::json::write string src]]
        } directoryMessage]
        set escapeCode [catch {
            $plugins invoke fossil_remove [::json::write object path \
                [::json::write string ../outside.tcl]]
        } escapeMessage]
        list \
            $deniedCode $deniedMessage $result \
            [lrange [lindex [lindex $::RunnerMock::calls 0] 0] 1 end] \
            $directoryCode $directoryMessage \
            $escapeCode $escapeMessage
    } finally {
        $plugins destroy
        $runner destroy
        file delete -force $root
    }
} -result [list \
    1 "Plugin execution denied: fossil_remove" \
    "sandboxed Tcl output" [list rm --hard -- src/obsolete.tcl] \
    1 "fossil_remove path is not an existing file: src" \
    1 "Plugin path escapes the workspace"]

test fossil-diff-1.1 {Fossil diff is internal and path-confined} -body {
    set root [file normalize [file join \
        [::tcltest::temporaryDirectory] fossil-diff-[pid]]]
    file mkdir [file join $root src]
    set ::RunnerMock::calls {}
    set runner [::tProcessRunner new \
        $root tclsh9.0 direct bwrap 2500 4096 ::RunnerMock::execute]
    set plugins [::tPluginRegistry new \
        $root [list [file join $projectDir plugins]] \
        "" 1000 65536 {} "" "" $runner]
    try {
        set allResult [$plugins invoke fossil_diff \
            [::json::write object]]
        set fileResult [$plugins invoke fossil_diff [::json::write object \
            path [::json::write string src/client.tcl]]]
        set escapeCode [catch {
            $plugins invoke fossil_diff [::json::write object \
                path [::json::write string ../outside.tcl]]
        } escapeMessage]
        list \
            $allResult \
            [lrange [lindex [lindex $::RunnerMock::calls 0] 0] 1 end] \
            $fileResult \
            [lrange [lindex [lindex $::RunnerMock::calls 1] 0] 1 end] \
            $escapeCode $escapeMessage
    } finally {
        $plugins destroy
        $runner destroy
        file delete -force $root
    }
} -result [list \
    "sandboxed Tcl output" [list diff -i] \
    "sandboxed Tcl output" [list diff -i -- src/client.tcl] \
    1 "Plugin path escapes the workspace"]

test fossil-timeline-1.1 {Fossil timeline is concise and bounded} -body {
    set root [file normalize [file join \
        [::tcltest::temporaryDirectory] fossil-timeline-[pid]]]
    file mkdir $root
    set ::RunnerMock::calls {}
    set runner [::tProcessRunner new \
        $root tclsh9.0 direct bwrap 2500 4096 ::RunnerMock::execute]
    set plugins [::tPluginRegistry new \
        $root [list [file join $projectDir plugins]] \
        "" 1000 65536 {} "" "" $runner]
    try {
        set defaultResult [$plugins invoke fossil_timeline \
            [::json::write object]]
        set selectedResult [$plugins invoke fossil_timeline \
            [::json::write object limit 50]]
        set excessiveCode [catch {
            $plugins invoke fossil_timeline \
                [::json::write object limit 101]
        } excessiveMessage]
        list \
            $defaultResult \
            [lrange [lindex [lindex $::RunnerMock::calls 0] 0] 1 end] \
            $selectedResult \
            [lrange [lindex [lindex $::RunnerMock::calls 1] 0] 1 end] \
            $excessiveCode $excessiveMessage
    } finally {
        $plugins destroy
        $runner destroy
        file delete -force $root
    }
} -result [list \
    "sandboxed Tcl output" \
    [list timeline -t ci -n 20 --oneline -q] \
    "sandboxed Tcl output" \
    [list timeline -t ci -n 50 --oneline -q] \
    1 "fossil_timeline limit exceeds configured maximum: 100"]

test plugins-1.1 {built-in plugins are discovered and invoked} -body {
    set registry [::tPluginRegistry new \
        $projectDir [list [file join $projectDir plugins]]]

    try {
        set fileContent [$registry invoke read_file [::json::write object \
            path [::json::write string "main.tcl"]]]
        set fileList [$registry invoke list_files [::json::write object]]

        list \
            [$registry names] \
            [expr {[string first "proc ::main" $fileContent] >= 0}] \
            [expr {"main.tcl" in [split $fileList "\n"]}] \
            [expr {"plugins/" in [split $fileList "\n"]}] \
            [lmap definition [$registry definitions] {
                dict get $definition name
            }]
    } finally {
        $registry destroy
    }
} -result [list \
    [list apply_patch copy_file delete_file edit_file file_info fossil_add fossil_branch_close fossil_branch_info fossil_branch_new fossil_branch_reopen fossil_branch_switch fossil_branches fossil_changes fossil_commit fossil_diff fossil_extras fossil_info fossil_ls fossil_merge fossil_pull fossil_push fossil_redo fossil_remove fossil_revert fossil_stash_list fossil_stash_pop fossil_stash_save fossil_status fossil_timeline fossil_undo fossil_update http_delete http_get http_patch http_post http_put list_files make_directory move_file oodz_lookup oodz_read oodz_search read_file save_translation search_files write_file xml_validate] \
    1 1 1 \
    [list apply_patch copy_file delete_file edit_file file_info fossil_add fossil_branch_close fossil_branch_info fossil_branch_new fossil_branch_reopen fossil_branch_switch fossil_branches fossil_changes fossil_commit fossil_diff fossil_extras fossil_info fossil_ls fossil_merge fossil_pull fossil_push fossil_redo fossil_remove fossil_revert fossil_stash_list fossil_stash_pop fossil_stash_save fossil_status fossil_timeline fossil_undo fossil_update http_delete http_get http_patch http_post http_put list_files make_directory move_file oodz_lookup oodz_read oodz_search read_file save_translation search_files write_file xml_validate]]

test plugins-settings-1.1 {private settings reach only the plugin handler} -body {
    set registry [::tPluginRegistry new \
        $projectDir [list \
            [file join $projectDir tests fixtures settings_plugins]]]
    try {
        set definitions [$registry definitions]
        set result [$registry invoke settings_test \
            [::json::write object]]
        list \
            $result \
            [dict exists [lindex $definitions 0] settings] \
            [expr {[string first "127.0.0.1" $definitions] < 0}] \
            [expr {[string first "never-model-visible" $definitions] < 0}]
    } finally {
        $registry destroy
    }
} -result [list http://127.0.0.1:8080 0 1 1]

test http-get-1.1 {HTTP GET URL is scoped and query encoded offline} -body {
    set registry [::tPluginRegistry new \
        $projectDir [list [file join $projectDir plugins]]]
    try {
        set registryNamespace [info object namespace $registry]
        set pluginInterpreter \
            [set ${registryNamespace}::pluginInterpreter]
        set settings [dict create \
            base_url http://127.0.0.1:8080 \
            allowed_path_prefixes /api/,/health]
        set url [interp eval $pluginInterpreter [list \
            ::plugins::http_get::buildUrl \
            [dict create path /api/v2/client query [dict create \
                search "José Silva" page 2]] \
            $settings]]
        set results [list $url]
        foreach path {
            https://example.com/api/
            //example.com/api/
            /api/../secret
            /other/path
            {/api/test?bad=1}
            {/api/test#fragment}
        } {
            lappend results [catch {
                interp eval $pluginInterpreter [list \
                    ::plugins::http_get::buildUrl \
                    [dict create path $path] $settings]
            }]
        }
        set results
    } finally {
        $registry destroy
    }
} -result [list \
    {http://127.0.0.1:8080/api/v2/client?search=Jos%C3%A9%20Silva&page=2} \
    1 1 1 1 1 1]

test http-get-1.2 {TLS verification supports private development servers} -body {
    set registry [::tPluginRegistry new \
        $projectDir [list [file join $projectDir plugins]]]
    set channel [file tempfile caPath]
    puts $channel "test CA fixture"
    close $channel
    try {
        set registryNamespace [info object namespace $registry]
        set pluginInterpreter \
            [set ${registryNamespace}::pluginInterpreter]
        set insecure [interp eval $pluginInterpreter [list \
            ::plugins::http_get::tlsOptions \
            [dict create tls_verify false]]]
        set verified [interp eval $pluginInterpreter [list \
            ::plugins::http_get::tlsOptions \
            [dict create tls_verify true tls_ca_file $caPath]]]
        set invalidCode [catch {
            interp eval $pluginInterpreter [list \
                ::plugins::http_get::tlsOptions \
                [dict create tls_verify sometimes]]
        } invalidMessage]
        list \
            [lindex $insecure [expr {[lsearch $insecure -require] + 1}]] \
            [lindex $verified [expr {[lsearch $verified -require] + 1}]] \
            [expr {[lindex $verified \
                [expr {[lsearch $verified -cafile] + 1}]] eq \
                [file normalize $caPath]}] \
            $invalidCode $invalidMessage
    } finally {
        file delete $caPath
        $registry destroy
    }
} -result [list 0 1 1 1 \
    "http_get setting must be boolean: tls_verify"]

test http-post-1.1 {HTTP POST validates scoped URLs and native JSON offline} -body {
    set registry [::tPluginRegistry new \
        $projectDir [list [file join $projectDir plugins]]]
    try {
        set registryNamespace [info object namespace $registry]
        set pluginInterpreter \
            [set ${registryNamespace}::pluginInterpreter]
        set settings [dict create \
            base_url https://127.0.0.1/api/v2 \
            allowed_path_prefixes /translate/,/tax]
        set arguments [dict create \
            path /translate/add_new_line \
            query [dict create source "OODZ test"]]
        set url [interp eval $pluginInterpreter [list \
            ::plugins::http_post::buildUrl $arguments $settings]]
        set jsonBody \
            {{"original":"Bottle","ru_ru":"Бутылка","ch_ch":"瓶子","active":true,"rate":21}}
        set preserved [interp eval $pluginInterpreter [list \
            ::plugins::http_post::validateJson $jsonBody]]
        set malformedCode [catch {
            interp eval $pluginInterpreter [list \
                ::plugins::http_post::validateJson \
                {{"original":broken}}]
        } malformedMessage]
        set arrayCode [catch {
            interp eval $pluginInterpreter [list \
                ::plugins::http_post::validateJson {[1,2,3]}]
        } arrayMessage]
        list $url [expr {$preserved eq $jsonBody}] \
            $malformedCode $malformedMessage $arrayCode $arrayMessage
    } finally {
        $registry destroy
    }
} -result [list \
    {https://127.0.0.1/api/v2/translate/add_new_line?source=OODZ%20test} \
    1 1 "http_post json is not valid JSON" \
    1 "http_post json must be a JSON object"]

test http-write-verbs-1.1 {PUT, PATCH and DELETE expose approved schemas} -body {
    set registry [::tPluginRegistry new \
        $projectDir [list [file join $projectDir plugins]]]
    try {
        set registryNamespace [info object namespace $registry]
        set plugins [set ${registryNamespace}::plugins]
        set definitions [dict create]
        foreach definition [$registry definitions] {
            dict set definitions [dict get $definition name] $definition
        }
        list \
            [dict get $plugins http_put permission] \
            [dict get $plugins http_patch permission] \
            [dict get $plugins http_delete permission] \
            [dict get $definitions http_put parameters required] \
            [dict get $definitions http_patch parameters required] \
            [dict get $definitions http_delete parameters required] \
            [dict exists $definitions http_delete parameters properties json]
    } finally {
        $registry destroy
    }
} -result [list \
    write write write \
    [list path json] [list path json] [list path] 1]

test http-headers-1.1 {private HTTP headers are validated offline} -body {
    set registry [::tPluginRegistry new \
        $projectDir [list [file join $projectDir plugins]]]
    try {
        set registryNamespace [info object namespace $registry]
        set pluginInterpreter \
            [set ${registryNamespace}::pluginInterpreter]
        set valid [interp eval $pluginInterpreter [list \
            ::plugins::http_common::customHeaders http_get [dict create \
                header.Authorization "Bearer private-token" \
                header.X-API-Key "secret-key"]]]
        set managedCode [catch {
            interp eval $pluginInterpreter [list \
                ::plugins::http_common::customHeaders http_get [dict create \
                    header.Content-Type text/plain]]
        } managedMessage]
        set newlineCode [catch {
            interp eval $pluginInterpreter [list \
                ::plugins::http_common::customHeaders http_get [dict create \
                    header.X-Test "safe\r\nInjected: bad"]]
        } newlineMessage]
        list $valid $managedCode $managedMessage \
            $newlineCode $newlineMessage
    } finally {
        $registry destroy
    }
} -result [list \
    [list Accept application/json \
        Authorization "Bearer private-token" X-API-Key secret-key] \
    1 "http_get custom header is managed internally: Content-Type" \
    1 "http_get custom header value contains a newline: X-Test"]

test http-transport-1.1 {HTTP verbs assemble exact requests offline} -body {
    set registry [::tPluginRegistry new \
        $projectDir [list [file join $projectDir plugins]]]
    try {
        set registryNamespace [info object namespace $registry]
        set pluginInterpreter \
            [set ${registryNamespace}::pluginInterpreter]
        interp eval $pluginInterpreter {
            namespace eval ::http_mock {
                variable calls {}
            }
            foreach command {geturl status ncode data error cleanup} {
                rename ::http::$command ::http::real_$command
            }
            proc ::http::geturl {url args} {
                variable ::http_mock::calls
                lappend calls [list $url $args]
                return mock-token
            }
            proc ::http::status {token} { return ok }
            proc ::http::ncode {token} { return 200 }
            proc ::http::data {token} {
                encoding convertto utf-8 {{"ok":true}}
            }
            proc ::http::error {token} { return "" }
            proc ::http::cleanup {token} { return }
        }

        set settings [dict create \
            base_url http://127.0.0.1:8080/api/v2 \
            allowed_path_prefixes / \
            header.Authorization "Bearer private-token" \
            header.X-Client-Id oodz-agent]
        set jsonBody \
            {{"label":"Бутылка","ch_ch":"瓶子","active":true,"rate":21}}
        foreach call [list \
            [list ::plugins::http_get::execute \
                [dict create path /items query [dict create page 2]]] \
            [list ::plugins::http_post::execute \
                [dict create path /items json $jsonBody]] \
            [list ::plugins::http_put::execute \
                [dict create path /items/1 json $jsonBody]] \
            [list ::plugins::http_patch::execute \
                [dict create path /items/1 json $jsonBody]] \
            [list ::plugins::http_delete::execute \
                [dict create path /items/1]] \
            [list ::plugins::http_delete::execute \
                [dict create path /items/2 json $jsonBody]]] {
            lassign $call handler arguments
            interp eval $pluginInterpreter [list \
                $handler $projectDir $arguments $settings]
        }

        set calls [interp eval $pluginInterpreter {
            set ::http_mock::calls
        }]
        set summary {}
        foreach call $calls {
            lassign $call url optionsList
            set options [dict create {*}$optionsList]
            set headers [dict create {*}[dict get $options -headers]]
            set body ""
            if {[dict exists $options -query]} {
                set body [encoding convertfrom utf-8 \
                    [dict get $options -query]]
            }
            lappend summary [list \
                [dict get $options -method] \
                $url \
                [dict get $headers Authorization] \
                [dict get $headers X-Client-Id] \
                [expr {[dict exists $options -type]
                    ? [dict get $options -type] : ""}] \
                $body]
        }
        set summary
    } finally {
        $registry destroy
    }
} -result [list \
    [list GET {http://127.0.0.1:8080/api/v2/items?page=2} \
        "Bearer private-token" oodz-agent "" ""] \
    [list POST http://127.0.0.1:8080/api/v2/items \
        "Bearer private-token" oodz-agent \
        "application/json; charset=utf-8" \
        {{"label":"Бутылка","ch_ch":"瓶子","active":true,"rate":21}}] \
    [list PUT http://127.0.0.1:8080/api/v2/items/1 \
        "Bearer private-token" oodz-agent \
        "application/json; charset=utf-8" \
        {{"label":"Бутылка","ch_ch":"瓶子","active":true,"rate":21}}] \
    [list PATCH http://127.0.0.1:8080/api/v2/items/1 \
        "Bearer private-token" oodz-agent \
        "application/json; charset=utf-8" \
        {{"label":"Бутылка","ch_ch":"瓶子","active":true,"rate":21}}] \
    [list DELETE http://127.0.0.1:8080/api/v2/items/1 \
        "Bearer private-token" oodz-agent "" ""] \
    [list DELETE http://127.0.0.1:8080/api/v2/items/2 \
        "Bearer private-token" oodz-agent \
        "application/json; charset=utf-8" \
        {{"label":"Бутылка","ch_ch":"瓶子","active":true,"rate":21}}]]

test http-transport-1.2 {HTTP response status and limits are handled offline} -body {
    set registry [::tPluginRegistry new \
        $projectDir [list [file join $projectDir plugins]]]
    try {
        set registryNamespace [info object namespace $registry]
        set pluginInterpreter \
            [set ${registryNamespace}::pluginInterpreter]
        interp eval $pluginInterpreter {
            namespace eval ::http_mock {
                variable responseCode 422
                variable responseData [encoding convertto utf-8 \
                    {{"error":"invalid input"}}]
            }
            foreach command {geturl status ncode data error cleanup} {
                rename ::http::$command ::http::real_$command
            }
            proc ::http::geturl {url args} { return mock-token }
            proc ::http::status {token} { return ok }
            proc ::http::ncode {token} {
                set ::http_mock::responseCode
            }
            proc ::http::data {token} {
                set ::http_mock::responseData
            }
            proc ::http::error {token} { return "" }
            proc ::http::cleanup {token} { return }
        }
        set settings [dict create \
            base_url http://127.0.0.1:8080 \
            allowed_path_prefixes / \
            max_response_chars 1024]
        set response [interp eval $pluginInterpreter [list \
            ::plugins::http_get::execute $projectDir \
            [dict create path /invalid] $settings]]
        interp eval $pluginInterpreter {
            set ::http_mock::responseData [string repeat x 20]
        }
        dict set settings max_response_chars 10
        set limitCode [catch {
            interp eval $pluginInterpreter [list \
                ::plugins::http_get::execute $projectDir \
                [dict create path /large] $settings]
        } limitMessage]
        list $response $limitCode $limitMessage
    } finally {
        $registry destroy
    }
} -result [list \
    "HTTP 422\n{\"error\":\"invalid input\"}" \
    1 "http_get response exceeds configured limit"]

test skills-tool-1.1 {load_skill exposes one selected workflow on demand} -body {
    set skills [::tSkillRegistry new [list [file join $projectDir skills]]]
    set registry [::tPluginRegistry new \
        $projectDir [list [file join $projectDir plugins]] \
        "" 1000 65536 {} $skills]
    set config [::FakeConfig new [dict create LLM.api_key test-only-key]]
    set client [::tLLMClient new $config]
    try {
        set definitionNames [lmap definition [$registry definitions] {
            dict get $definition name
        }]
        set payload [::json::json2dict [$client buildPayload \
            system [list [dict create role user content test]] \
            [$registry definitions]]]
        set loadDefinition {}
        foreach definition [dict get $payload tools] {
            if {[dict get $definition function name] eq "load_skill"} {
                set loadDefinition $definition
                break
            }
        }
        set instructions [$registry invoke load_skill \
            [::json::write object name \
                [::json::write string create-oodz-class]]]
        list \
            [expr {"load_skill" in [$registry names]}] \
            [expr {"load_skill" in $definitionNames}] \
            [dict get $loadDefinition function parameters type] \
            [expr {[string first "Use `oodz_lookup`" $instructions] >= 0}]
    } finally {
        $client destroy
        $config destroy
        $registry destroy
        $skills destroy
    }
} -result [list 1 1 object 1]

test search-files-1.1 {search_files finds bounded nested literal matches} -body {
    set temporaryRoot [file join [temporaryDirectory] \
        "oodz-search-test-[pid]-[clock clicks]"]
    file mkdir [file join $temporaryRoot nested]
    set rootChannel [open [file join $temporaryRoot root.txt] w]
    puts $rootChannel "A NEEDLE in the root."
    close $rootChannel
    set nestedChannel [open [file join $temporaryRoot nested code.tcl] w]
    puts $nestedChannel "first line"
    puts $nestedChannel "a needle in nested code"
    close $nestedChannel
    set registry [::tPluginRegistry new \
        $temporaryRoot [list [file join $projectDir plugins]]]

    try {
        set matches [$registry invoke search_files [::json::write object \
            query [::json::write string "needle"]]]
        set noMatches [$registry invoke search_files [::json::write object \
            query [::json::write string "absent"] \
            path [::json::write string "nested"]]]
        set emptyResult [catch {
            $registry invoke search_files [::json::write object \
                query [::json::write string ""]]
        } emptyMessage]
        set escapeResult [catch {
            $registry invoke search_files [::json::write object \
                query [::json::write string "needle"] \
                path [::json::write string "../outside"]]
        } escapeMessage]

        list \
            [expr {[string first "root.txt:1:" $matches] >= 0}] \
            [expr {[string first "nested/code.tcl:2:" $matches] >= 0}] \
            $noMatches \
            $emptyResult $emptyMessage \
            $escapeResult $escapeMessage
    } finally {
        $registry destroy
        file delete -force $temporaryRoot
    }
} -result [list \
    1 1 \
    "No matches found." \
    1 "Search query must not be empty" \
    1 "Plugin path escapes the workspace"]

test oodz-lookup-1.1 {oodz_lookup finds compact framework capabilities} -body {
    set registry [::tPluginRegistry new \
        $projectDir [list [file join $projectDir plugins]]]
    try {
        set sqlResult [$registry invoke oodz_lookup [::json::write object \
            query [::json::write string "date range"]]]
        set baseResult [$registry invoke oodz_lookup [::json::write object \
            query [::json::write string "baseObj"]]]
        set missingResult [$registry invoke oodz_lookup [::json::write object \
            query [::json::write string "nonexistent capability"]]]
        set emptyCode [catch {
            $registry invoke oodz_lookup [::json::write object \
                query [::json::write string ""]]
        } emptyMessage]
        list \
            [expr {[string first "Name: ::SQLBuilder" $sqlResult] >= 0}] \
            [expr {[string first "Source: db/SelectSqlBuilder.tcl" \
                $sqlResult] >= 0}] \
            [expr {[string first "Name: ::oodz::baseObj" \
                $baseResult] >= 0}] \
            $missingResult $emptyCode $emptyMessage
    } finally {
        $registry destroy
    }
} -result [list \
    1 1 1 \
    "No OODZ components found for: nonexistent capability" \
    1 "OODZ lookup query must not be empty"]

test oodz-read-1.1 {oodz_read returns confined bounded numbered UTF-8 lines} -body {
    set temporaryRoot [file join [temporaryDirectory] \
        "oodz-read-test-[pid]-[clock clicks]"]
    set referenceRoot [file join $temporaryRoot framework]
    file mkdir [file join $referenceRoot base]
    set sourcePath [file join $referenceRoot base sample.tcl]
    set sourceChannel [open $sourcePath wb]
    puts -nonewline $sourceChannel [encoding convertto utf-8 \
        "line one\nстрока два\n行三\nline four"]
    close $sourceChannel
    set binaryPath [file join $referenceRoot binary.dat]
    set binaryChannel [open $binaryPath wb]
    puts -nonewline $binaryChannel [binary format H* 410042]
    close $binaryChannel
    set registry [::tPluginRegistry new \
        $temporaryRoot [list [file join $projectDir plugins]] \
        "" 1000 65536 [dict create oodz $referenceRoot]]

    try {
        set result [$registry invoke oodz_read [::json::write object \
            path [::json::write string base/sample.tcl] \
            start_line 2 end_line 3]]
        set escapeCode [catch {
            $registry invoke oodz_read [::json::write object \
                path [::json::write string ../outside.tcl]]
        } escapeMessage]
        set rangeCode [catch {
            $registry invoke oodz_read [::json::write object \
                path [::json::write string base/sample.tcl] \
                start_line 1 end_line 201]
        } rangeMessage]
        set binaryCode [catch {
            $registry invoke oodz_read [::json::write object \
                path [::json::write string binary.dat]]
        } binaryMessage]
        list $result \
            $escapeCode $escapeMessage \
            $rangeCode $rangeMessage \
            $binaryCode $binaryMessage
    } finally {
        $registry destroy
        file delete -force $temporaryRoot
    }
} -result [list \
    "2: строка два\n3: 行三" \
    1 "Reference path escapes configured root: oodz" \
    1 "OODZ reads are limited to 200 lines" \
    1 "OODZ file appears to be binary: binary.dat"]

test oodz-search-1.1 {oodz_search finds bounded source matches and skips internals} -body {
    set temporaryRoot [file join [temporaryDirectory] \
        "oodz-framework-search-test-[pid]-[clock clicks]"]
    set referenceRoot [file join $temporaryRoot framework]
    file mkdir [file join $referenceRoot base] \
        [file join $referenceRoot nested] \
        [file join $referenceRoot .git] \
        [file join $referenceRoot tmp]
    foreach {relativePath content} [list \
            base/baseObj.tcl "first\n:public method save2db {} {\n}\n" \
            nested/unicode.tcl "метод сохранения SAVE2DB\n" \
            .git/ignored.tcl "save2db\n" \
            tmp/ignored.tcl "save2db\n"] {
        set channel [open [file join $referenceRoot $relativePath] wb]
        puts -nonewline $channel [encoding convertto utf-8 $content]
        close $channel
    }
    set registry [::tPluginRegistry new \
        $temporaryRoot [list [file join $projectDir plugins]] \
        "" 1000 65536 [dict create oodz $referenceRoot]]

    try {
        set matches [$registry invoke oodz_search [::json::write object \
            query [::json::write string save2db]]]
        set scoped [$registry invoke oodz_search [::json::write object \
            query [::json::write string save2db] \
            path [::json::write string base]]]
        set absent [$registry invoke oodz_search [::json::write object \
            query [::json::write string absent]]]
        set escapeCode [catch {
            $registry invoke oodz_search [::json::write object \
                query [::json::write string save2db] \
                path [::json::write string ../outside]]
        } escapeMessage]
        list \
            [expr {[string first "base/baseObj.tcl:2:" $matches] >= 0}] \
            [expr {[string first "nested/unicode.tcl:1:" $matches] >= 0}] \
            [expr {[string first ".git/" $matches] < 0}] \
            [expr {[string first "tmp/" $matches] < 0}] \
            [expr {[string first "base/baseObj.tcl:2:" $scoped] >= 0}] \
            $absent $escapeCode $escapeMessage
    } finally {
        $registry destroy
        file delete -force $temporaryRoot
    }
} -result [list \
    1 1 1 1 1 \
    "No OODZ matches found." \
    1 "Reference path escapes configured root: oodz"]

test file-info-1.1 {file_info reports stable metadata and rejects missing paths} -body {
    set temporaryRoot [file join [temporaryDirectory] \
        "oodz-info-test-[pid]-[clock clicks]"]
    file mkdir $temporaryRoot
    set target [file join $temporaryRoot sample.txt]
    set channel [open $target w]
    puts -nonewline $channel "hello"
    close $channel
    set registry [::tPluginRegistry new \
        $temporaryRoot [list [file join $projectDir plugins]]]

    try {
        set result [$registry invoke file_info [::json::write object \
            path [::json::write string sample.txt]]]
        set missingCode [catch {
            $registry invoke file_info [::json::write object \
                path [::json::write string missing.txt]]
        } missingMessage]
        list \
            [expr {[string first "Path: sample.txt" $result] >= 0}] \
            [expr {[string first "Type: file" $result] >= 0}] \
            [expr {[string first "Size: 5 bytes" $result] >= 0}] \
            $missingCode $missingMessage
    } finally {
        $registry destroy
        file delete -force $temporaryRoot
    }
} -result [list 1 1 1 1 "Path does not exist: missing.txt"]

test xml-validate-1.1 {xml_validate accepts valid XML and explains invalid XML} -body {
    set temporaryRoot [file join [temporaryDirectory] \
        "oodz-xml-test-[pid]-[clock clicks]"]
    file mkdir $temporaryRoot
    set validPath [file join $temporaryRoot valid.xml]
    set invalidPath [file join $temporaryRoot invalid.xml]
    foreach {path content} [list \
            $validPath {<?xml version="1.0" encoding="UTF-8"?><layout><row/></layout>} \
            $invalidPath {<layout><row></layout>}] {
        set channel [open $path w]
        fconfigure $channel -encoding utf-8
        puts -nonewline $channel $content
        close $channel
    }
    set registry [::tPluginRegistry new \
        $temporaryRoot [list [file join $projectDir plugins]]]

    try {
        set valid [$registry invoke xml_validate [::json::write object \
            path [::json::write string valid.xml]]]
        set invalidCode [catch {
            $registry invoke xml_validate [::json::write object \
                path [::json::write string invalid.xml]]
        } invalidMessage]
        set missingCode [catch {
            $registry invoke xml_validate [::json::write object \
                path [::json::write string missing.xml]]
        } missingMessage]
        list $valid $invalidCode \
            [string match {Invalid XML in invalid.xml:*} $invalidMessage] \
            $missingCode $missingMessage
    } finally {
        $registry destroy
        file delete -force $temporaryRoot
    }
} -result [list \
    "Valid XML: valid.xml\nRoot element: layout" \
    1 1 1 "XML file does not exist: missing.xml"]

test save-translation-1.1 {save_translation dry run validates its JSON without HTTP} -body {
    set registry [::tPluginRegistry new \
        $projectDir [list [file join $projectDir plugins]] \
        [list ::ApprovalMock::decide] 1000]
    set arguments [::json::write object \
        original [::json::write string "Customer address"] \
        pt_pt [::json::write string "Endereço do cliente"] \
        ch_ch [::json::write string "客户地址"] \
        ru_ru [::json::write string "Адрес клиента"] \
        fr_fr [::json::write string "Adresse du client"] \
        es_es [::json::write string "Dirección del cliente"] \
        en_us [::json::write string "Customer address"] \
        dry_run true]
    set transliteratedArguments [::json::write object \
        original [::json::write string "Bottle"] \
        pt_pt [::json::write string "Garrafa"] \
        ch_ch [::json::write string "瓶子"] \
        ru_ru [::json::write string "Butylka"] \
        fr_fr [::json::write string "Bouteille"] \
        es_es [::json::write string "Botella"] \
        en_us [::json::write string "Bottle"] \
        dry_run true]

    try {
        set ::ApprovalMock::approved 1
        set result [$registry invoke save_translation $arguments]
        set registryNamespace [info object namespace $registry]
        set pluginInterpreter \
            [set ${registryNamespace}::pluginInterpreter]
        set legacyDecoded [interp eval $pluginInterpreter [list \
            ::plugins::save_translation::decodeResponseBody \
            [binary format H* e7]]]
        set utf8Decoded [interp eval $pluginInterpreter [list \
            ::plugins::save_translation::decodeResponseBody \
            [encoding convertto utf-8 "瓶子"]]]
        set transliterationCode [catch {
            $registry invoke save_translation $transliteratedArguments
        } transliterationMessage]
        set resultLines [split $result "\n"]
        set payload [::json::json2dict \
            [join [lrange $resultLines 1 end] "\n"]]
        list \
            [lindex $resultLines 0] \
            [dict get $payload original] \
            [dict get $payload ch_ch] \
            [dict get $payload pt_pt] \
            $legacyDecoded $utf8Decoded \
            $transliterationCode $transliterationMessage
    } finally {
        $registry destroy
    }
} -result [list \
    "Dry run; no request sent." \
    "Customer address" "客户地址" "Endereço do cliente" \
    "ç" "瓶子" \
    1 "Russian translation must contain Cyrillic characters; transliteration is not allowed"]

test plugins-1.2 {plugin calls reject invalid names, arguments, and paths} -body {
    set registry [::tPluginRegistry new \
        $projectDir [list [file join $projectDir plugins]]]

    try {
        set results {}
        foreach {name arguments} [list \
            unknown [::json::write object] \
            read_file "not JSON" \
            read_file [::json::write object] \
            list_files [::json::write object \
                extra [::json::write string "value"]] \
            read_file [::json::write object \
                path [::json::write string "../outside"]]] {
            lappend results [catch {
                $registry invoke $name $arguments
            } message] $message
        }
        set results
    } finally {
        $registry destroy
    }
} -result [list \
    1 "Unknown plugin: unknown" \
    1 "Invalid JSON arguments for plugin: read_file" \
    1 "Missing plugin argument for read_file: path" \
    1 "Unknown plugin argument for list_files: extra" \
    1 "Plugin path escapes the workspace"]

test plugins-1.3 {plugin discovery rejects invalid and duplicate manifests} -body {
    set invalidResult [catch {
        ::tPluginRegistry new $projectDir [list \
            [file join $projectDir tests fixtures invalid_plugin]]
    } invalidMessage]
    set duplicateResult [catch {
        ::tPluginRegistry new $projectDir [list \
            [file join $projectDir plugins] \
            [file join $projectDir plugins]]
    } duplicateMessage]

    list \
        $invalidResult $invalidMessage \
        $duplicateResult $duplicateMessage
} -result [list \
    1 "Invalid plugin manifest: missing description" \
    1 "Duplicate plugin name: apply_patch"]

test plugins-safety-1.1 {write approval, timeout, and output limits are enforced} -body {
    set safetyDirectory [file join \
        $projectDir tests fixtures safety_plugins]
    set noApproval [::tPluginRegistry new \
        $projectDir [list $safetyDirectory] "" 20 20]
    set denied [::tPluginRegistry new \
        $projectDir [list $safetyDirectory] \
        [list ::ApprovalMock::decide] 20 20]
    set approved [::tPluginRegistry new \
        $projectDir [list $safetyDirectory] \
        [list ::ApprovalMock::decide] 20 20]
    set slow [::tPluginRegistry new \
        $projectDir [list $safetyDirectory] "" 20 20]
    set large [::tPluginRegistry new \
        $projectDir [list $safetyDirectory] "" 20 20]

    try {
        set emptyArguments [::json::write object]
        set noApprovalResult [catch {
            $noApproval invoke write_test $emptyArguments
        } noApprovalMessage]

        set ::ApprovalMock::approved 0
        set ::ApprovalMock::calls {}
        set deniedResult [catch {
            $denied invoke write_test $emptyArguments
        } deniedMessage]

        set ::ApprovalMock::approved 1
        set approvedResult [$approved invoke write_test $emptyArguments]
        set approvalCalls $::ApprovalMock::calls
        set approvedNamespace [info object namespace $approved]
        set approvedInterpreter \
            [set ${approvedNamespace}::pluginInterpreter]
        set remainingLimit [interp limit $approvedInterpreter time]

        set slowResult [catch {
            $slow invoke slow_test $emptyArguments
        } slowMessage]
        set largeResult [catch {
            $large invoke large_test $emptyArguments
        } largeMessage]

        list \
            $noApprovalResult $noApprovalMessage \
            $deniedResult $deniedMessage \
            $approvedResult \
            [lmap call $approvalCalls {lindex $call 0}] \
            [dict get $remainingLimit -seconds] \
            [dict get $remainingLimit -milliseconds] \
            $slowResult $slowMessage \
            $largeResult $largeMessage
    } finally {
        foreach registry [list \
                $noApproval $denied $approved $slow $large] {
            $registry destroy
        }
    }
} -result [list \
    1 "Plugin approval required: write_test" \
    1 "Plugin execution denied: write_test" \
    "write executed" \
    [list write_test write_test] \
    {} {} \
    1 "Plugin execution timed out: slow_test" \
    1 "Plugin output exceeds limit: large_test"]

test write-file-1.1 {write_file requires approval and writes exact content} -body {
    set temporaryRoot [file join [temporaryDirectory] \
        "oodz-write-test-[pid]-[clock clicks]"]
    file mkdir $temporaryRoot
    set registry [::tPluginRegistry new \
        $temporaryRoot \
        [list [file join $projectDir plugins]] \
        [list ::ApprovalMock::decide]]
    set arguments [::json::write object \
        path [::json::write string "created.txt"] \
        content [::json::write string "hello café\n"]]

    try {
        set ::ApprovalMock::approved 0
        set deniedResult [catch {
            $registry invoke write_file $arguments
        } deniedMessage]
        set existsAfterDenial [file exists \
            [file join $temporaryRoot created.txt]]

        set ::ApprovalMock::approved 1
        set approvedResult [$registry invoke write_file $arguments]
        set channel [open [file join $temporaryRoot created.txt] r]
        try {
            fconfigure $channel -encoding utf-8
            set writtenContent [read $channel]
        } finally {
            close $channel
        }

        list \
            $deniedResult $deniedMessage $existsAfterDenial \
            $approvedResult $writtenContent
    } finally {
        $registry destroy
        file delete -force $temporaryRoot
    }
} -result [list \
    1 "Plugin execution denied: write_file" 0 \
    "Wrote file: created.txt" "hello café\n"]

test make-directory-1.1 {make_directory is approved, recursive, and confined} -body {
    set temporaryRoot [file join [temporaryDirectory] \
        "oodz-mkdir-test-[pid]-[clock clicks]"]
    file mkdir $temporaryRoot
    set registry [::tPluginRegistry new \
        $temporaryRoot [list [file join $projectDir plugins]] \
        [list ::ApprovalMock::decide]]
    set nestedArguments [::json::write object \
        path [::json::write string "nested/deep"]]
    set escapeArguments [::json::write object \
        path [::json::write string "../outside"]]
    set occupiedPath [file join $temporaryRoot occupied]
    set occupiedChannel [open $occupiedPath w]
    close $occupiedChannel
    set occupiedArguments [::json::write object \
        path [::json::write string occupied]]

    try {
        set ::ApprovalMock::approved 0
        set deniedCode [catch {
            $registry invoke make_directory $nestedArguments
        } deniedMessage]
        set existsAfterDenial [file exists \
            [file join $temporaryRoot nested]]

        set ::ApprovalMock::approved 1
        set created [$registry invoke make_directory $nestedArguments]
        set nestedExists [file isdirectory \
            [file join $temporaryRoot nested deep]]
        set repeated [$registry invoke make_directory $nestedArguments]
        set escapeCode [catch {
            $registry invoke make_directory $escapeArguments
        } escapeMessage]
        set occupiedCode [catch {
            $registry invoke make_directory $occupiedArguments
        } occupiedMessage]

        list \
            $deniedCode $deniedMessage $existsAfterDenial \
            $created $nestedExists $repeated \
            $escapeCode $escapeMessage \
            $occupiedCode $occupiedMessage
    } finally {
        $registry destroy
        file delete -force $temporaryRoot
    }
} -result [list \
    1 "Plugin execution denied: make_directory" 0 \
    "Created directory: nested/deep" 1 \
    "Directory already exists: nested/deep" \
    1 "Plugin path escapes the workspace" \
    1 "Target exists and is not a directory: occupied"]

test edit-file-1.1 {edit_file performs one approved exact replacement} -body {
    set temporaryRoot [file join [temporaryDirectory] \
        "oodz-edit-test-[pid]-[clock clicks]"]
    file mkdir $temporaryRoot
    set target [file join $temporaryRoot sample.txt]
    set channel [open $target w]
    fconfigure $channel -encoding utf-8
    puts -nonewline $channel "alpha\ncafé\nomega\n"
    close $channel
    set registry [::tPluginRegistry new \
        $temporaryRoot [list [file join $projectDir plugins]] \
        [list ::ApprovalMock::decide]]
    set exactArguments [::json::write object \
        path [::json::write string sample.txt] \
        old_text [::json::write string "café"] \
        new_text [::json::write string "edited"]]

    try {
        set ::ApprovalMock::approved 0
        set deniedCode [catch {
            $registry invoke edit_file $exactArguments
        } deniedMessage]

        set ::ApprovalMock::approved 1
        set edited [$registry invoke edit_file $exactArguments]
        set channel [open $target r]
        fconfigure $channel -encoding utf-8
        set content [read $channel]
        close $channel

        set missingCode [catch {
            $registry invoke edit_file [::json::write object \
                path [::json::write string sample.txt] \
                old_text [::json::write string absent] \
                new_text [::json::write string replacement]]
        } missingMessage]

        set channel [open $target w]
        puts -nonewline $channel "same same"
        close $channel
        set ambiguousCode [catch {
            $registry invoke edit_file [::json::write object \
                path [::json::write string sample.txt] \
                old_text [::json::write string same] \
                new_text [::json::write string changed]]
        } ambiguousMessage]

        list \
            $deniedCode $deniedMessage \
            $edited $content \
            $missingCode $missingMessage \
            $ambiguousCode $ambiguousMessage
    } finally {
        $registry destroy
        file delete -force $temporaryRoot
    }
} -result [list \
    1 "Plugin execution denied: edit_file" \
    "Edited file: sample.txt" "alpha\nedited\nomega\n" \
    1 "old_text was not found in: sample.txt" \
    1 "old_text appears more than once in: sample.txt"]

test filesystem-mutations-1.1 {copy, move, and delete files safely} -body {
    set temporaryRoot [file join [temporaryDirectory] \
        "oodz-mutations-test-[pid]-[clock clicks]"]
    file mkdir [file join $temporaryRoot nested]
    set source [file join $temporaryRoot source.txt]
    set channel [open $source w]
    puts -nonewline $channel "original"
    close $channel
    set registry [::tPluginRegistry new \
        $temporaryRoot [list [file join $projectDir plugins]] \
        [list ::ApprovalMock::decide]]
    set copyArguments [::json::write object \
        source [::json::write string source.txt] \
        destination [::json::write string nested/copied.txt]]
    set moveArguments [::json::write object \
        source [::json::write string nested/copied.txt] \
        destination [::json::write string moved.txt]]
    set deleteArguments [::json::write object \
        path [::json::write string moved.txt]]

    try {
        set ::ApprovalMock::approved 0
        set deniedCode [catch {
            $registry invoke copy_file $copyArguments
        } deniedMessage]
        set ::ApprovalMock::approved 1
        set copied [$registry invoke copy_file $copyArguments]
        set overwriteCode [catch {
            $registry invoke copy_file $copyArguments
        } overwriteMessage]
        set moved [$registry invoke move_file $moveArguments]
        set deleted [$registry invoke delete_file $deleteArguments]
        set directoryCode [catch {
            $registry invoke delete_file [::json::write object \
                path [::json::write string nested]]
        } directoryMessage]

        list $deniedCode $deniedMessage \
            $copied $overwriteCode $overwriteMessage \
            $moved [file exists [file join $temporaryRoot nested copied.txt]] \
            $deleted [file exists [file join $temporaryRoot moved.txt]] \
            $directoryCode $directoryMessage
    } finally {
        $registry destroy
        file delete -force $temporaryRoot
    }
} -result [list \
    1 "Plugin execution denied: copy_file" \
    "Copied file: source.txt -> nested/copied.txt" \
    1 "Destination already exists: nested/copied.txt" \
    "Moved file: nested/copied.txt -> moved.txt" 0 \
    "Deleted file: moved.txt" 0 \
    1 "Path is not a file: nested"]

test apply-patch-1.1 {apply_patch makes multiple exact changes atomically} -body {
    set temporaryRoot [file join [temporaryDirectory] \
        "oodz-patch-test-[pid]-[clock clicks]"]
    file mkdir $temporaryRoot
    set target [file join $temporaryRoot sample.txt]
    set channel [open $target w]
    puts -nonewline $channel "alpha\nbeta\ngamma\n"
    close $channel
    set registry [::tPluginRegistry new \
        $temporaryRoot [list [file join $projectDir plugins]] \
        [list ::ApprovalMock::decide]]
    set patchText "<<<<<<< SEARCH\nalpha\n=======\nfirst\n>>>>>>> REPLACE\n<<<<<<< SEARCH\ngamma\n=======\nthird\n>>>>>>> REPLACE"
    set arguments [::json::write object \
        path [::json::write string sample.txt] \
        patch [::json::write string $patchText]]

    try {
        set ::ApprovalMock::approved 1
        set result [$registry invoke apply_patch $arguments]
        set channel [open $target r]
        set content [read $channel]
        close $channel
        set badPatch "<<<<<<< SEARCH\nmissing\n=======\nchanged\n>>>>>>> REPLACE"
        set failedCode [catch {
            $registry invoke apply_patch [::json::write object \
                path [::json::write string sample.txt] \
                patch [::json::write string $badPatch]]
        } failedMessage]
        set channel [open $target r]
        set contentAfterFailure [read $channel]
        close $channel
        list $result $content $failedCode $failedMessage $contentAfterFailure
    } finally {
        $registry destroy
        file delete -force $temporaryRoot
    }
} -result [list \
    "Applied patch to: sample.txt (2 change(s))" \
    "first\nbeta\nthird\n" \
    1 "Patch SEARCH text was not found in: sample.txt" \
    "first\nbeta\nthird\n"]

test write-file-1.2 {CLI approval accepts yes and defaults to denial} -body {
    set inputChannel [file tempfile inputPath]
    set outputChannel [file tempfile outputPath]
    try {
        puts $inputChannel "yes"
        puts $inputChannel "no"
        flush $inputChannel
        seek $inputChannel 0

        set arguments [dict create path "created.txt"]
        set yesResult [::requestPluginApproval \
            $inputChannel $outputChannel write_file $arguments]
        set noResult [::requestPluginApproval \
            $inputChannel $outputChannel write_file $arguments]
        flush $outputChannel
        seek $outputChannel 0

        list \
            $yesResult $noResult \
            [regexp -all {Allow write plugin 'write_file'} \
                [read $outputChannel]]
    } finally {
        close $inputChannel
        close $outputChannel
        file delete $inputPath $outputPath
    }
} -result [list 1 0 2]

test write-file-1.3 {CLI approval temporarily uses blocking input} -body {
    set inputChannel [file tempfile inputPath]
    set outputChannel [file tempfile outputPath]
    try {
        puts $inputChannel "y"
        flush $inputChannel
        seek $inputChannel 0
        fconfigure $inputChannel -blocking 0
        set approved [::requestPluginApproval \
            $inputChannel $outputChannel write_file \
            [dict create path sample.txt]]
        list $approved [fconfigure $inputChannel -blocking]
    } finally {
        close $inputChannel
        close $outputChannel
        file delete $inputPath $outputPath
    }
} -result [list 1 0]

test write-file-1.4 {all approves remaining writes for this session} -body {
    set inputChannel [file tempfile inputPath]
    set outputChannel [file tempfile outputPath]
    try {
        set ::approveAllWritesForSession 0
        puts $inputChannel "all"
        flush $inputChannel
        seek $inputChannel 0

        set arguments [dict create path "created.txt"]
        set firstResult [::requestPluginApproval \
            $inputChannel $outputChannel write_file $arguments]
        set secondResult [::requestPluginApproval \
            $inputChannel $outputChannel delete_file $arguments]
        flush $outputChannel
        seek $outputChannel 0

        list \
            $firstResult $secondResult \
            [regexp -all {Allow write plugin} [read $outputChannel]]
    } finally {
        set ::approveAllWritesForSession 0
        close $inputChannel
        close $outputChannel
        file delete $inputPath $outputPath
    }
} -result [list 1 1 1]

test write-file-1.5 {approve all never bypasses Tcl execution approval} -body {
    set inputChannel [file tempfile inputPath]
    set outputChannel [file tempfile outputPath]
    try {
        set ::approveAllWritesForSession 0
        puts $inputChannel "all"
        puts $inputChannel "y"
        puts $inputChannel "y"
        flush $inputChannel
        seek $inputChannel 0
        set arguments [dict create path script.tcl]
        set writeResult [::requestPluginApproval \
            $inputChannel $outputChannel write_file $arguments]
        set runnerResult [::requestPluginApproval \
            $inputChannel $outputChannel run_tcl_file $arguments]
        set projectResult [::requestPluginApproval \
            $inputChannel $outputChannel run_project_tests [dict create]]
        flush $outputChannel
        seek $outputChannel 0
        set prompts [read $outputChannel]
        list \
            $writeResult $runnerResult $projectResult \
            [expr {[string first "No OS sandbox may be active" \
                $prompts] >= 0}]
    } finally {
        set ::approveAllWritesForSession 0
        close $inputChannel
        close $outputChannel
        file delete $inputPath $outputPath
    }
} -result [list 1 1 1 1]

test agent-loop-1.1 {agent executes a plugin and returns the final answer} -body {
    set registry [::tPluginRegistry new \
        $projectDir [list [file join $projectDir plugins]]]
    set arguments [::json::write object \
        path [::json::write string "main.tcl"]]
    set toolCall [dict create \
        id "call_read" \
        type "function" \
        function [dict create name read_file arguments $arguments]]
    set client [::StructuredFakeLLMClient new [list \
        [dict create \
            role assistant \
            content "" \
            reasoning_content "I should inspect main.tcl." \
            tool_calls [list $toolCall]] \
        [dict create role assistant content "Inspection complete."]]]
    set agent [::tAgent new \
        TestAgent "Test system role" $client $registry 4]

    try {
        set answer [$agent run "Inspect main.tcl"]
        set calls [$client getCalls]
        set secondMessages [lindex [lindex $calls 1] 1]
        set toolResult [lindex $secondMessages end]

        list \
            $answer \
            [llength $calls] \
            [lmap definition [lindex [lindex $calls 0] 2] {
                dict get $definition name
            }] \
            [dict get [lindex $secondMessages 1] reasoning_content] \
            [dict get $toolResult role] \
            [dict get $toolResult tool_call_id] \
            [expr {[string first "proc ::main" \
                [dict get $toolResult content]] >= 0}] \
            [llength [$agent getHistory]]
    } finally {
        $agent destroy
        $client destroy
        $registry destroy
    }
} -result [list \
    "Inspection complete." \
    2 \
    [list apply_patch copy_file delete_file edit_file file_info fossil_add fossil_branch_close fossil_branch_info fossil_branch_new fossil_branch_reopen fossil_branch_switch fossil_branches fossil_changes fossil_commit fossil_diff fossil_extras fossil_info fossil_ls fossil_merge fossil_pull fossil_push fossil_redo fossil_remove fossil_revert fossil_stash_list fossil_stash_pop fossil_stash_save fossil_status fossil_timeline fossil_undo fossil_update http_delete http_get http_patch http_post http_put list_files make_directory move_file oodz_lookup oodz_read oodz_search read_file save_translation search_files write_file xml_validate] \
    "I should inspect main.tcl." \
    tool \
    call_read \
    1 \
    4]

test agent-loop-1.2 {tool-loop requests are re-bounded each iteration} -body {
    set firstCall [dict create id call_1 type function function [dict create \
        name list_files arguments {{}}]]
    set secondCall [dict create id call_2 type function function [dict create \
        name list_files arguments {{}}]]
    set client [::StructuredFakeLLMClient new [list \
        [dict create role assistant content "" tool_calls [list $firstCall]] \
        [dict create role assistant content "" tool_calls [list $secondCall]] \
        [dict create role assistant content done]]]
    set registry [::tPluginRegistry new \
        $projectDir [list [file join $projectDir plugins]]]
    set agent [::tAgent new \
        TestAgent "Test system role" $client $registry 4 "" 4]
    set oldHistory [list \
        [dict create role user content old-one] \
        [dict create role assistant content answer-one] \
        [dict create role user content old-two] \
        [dict create role assistant content answer-two]]
    try {
        $agent replaceHistory $oldHistory
        $agent run current
        set calls [$client getCalls]
        list \
            [lmap call $calls {llength [lindex $call 1]}] \
            [lmap message [lindex [lindex $calls end] 1] {
                dict get $message role
            }] \
            [llength [$agent getHistory]]
    } finally {
        $agent destroy
        $registry destroy
        $client destroy
    }
} -result [list \
    [list 3 3 5] \
    [list user assistant tool assistant tool] \
    10]

test agent-loop-1.2 {agent stops at the configured iteration limit} -body {
    set registry [::tPluginRegistry new \
        $projectDir [list [file join $projectDir plugins]]]
    set arguments [::json::write object]
    set toolCall [dict create \
        id "call_list" \
        type "function" \
        function [dict create name list_files arguments $arguments]]
    set response [dict create \
        role assistant content "" tool_calls [list $toolCall]]
    set client [::StructuredFakeLLMClient new [list $response $response]]
    set agent [::tAgent new \
        TestAgent "Test system role" $client $registry 2]

    try {
        set runResult [catch {
            $agent run "Keep listing files"
        } runMessage]
        list \
            $runResult $runMessage \
            [llength [$client getCalls]] \
            [$agent getHistory]
    } finally {
        $agent destroy
        $client destroy
        $registry destroy
    }
} -result [list \
    1 "Agent exceeded maximum iterations: 2" \
    2 [list \
        [dict create role user content "Keep listing files"] \
        [dict create role assistant content \
            "The previous task ended before a final response: Agent exceeded maximum iterations: 2"]]]

test cli-1.1 {CLI handles help, missing task, success, and failure} -body {
    set results {}

    foreach case {
        {help {--help} {}}
        {interactive {} {}}
        {success {write a loop} success}
        {failure {write a loop} failure}
    } {
        lassign $case name arguments clientType
        set client ""
        if {$clientType eq "success"} {
            set client [::FakeLLMClient new [list "CLI response"]]
        } elseif {$clientType eq "failure"} {
            set client [::FailingLLMClient new]
        }

        set inputChannel [file tempfile inputPath]
        set outChannel [file tempfile outPath]
        set errChannel [file tempfile errPath]
        try {
            if {$name eq "interactive"} {
                puts $inputChannel "/exit"
            }
            flush $inputChannel
            seek $inputChannel 0
            set exitCode [::main \
                $projectDir $arguments $client \
                $outChannel $errChannel $inputChannel]
            flush $outChannel
            flush $errChannel
            seek $outChannel 0
            seek $errChannel 0
            lappend results [list \
                $name $exitCode \
                [string trim [read $outChannel]] \
                [string trim [read $errChannel]]]
        } finally {
            close $inputChannel
            close $outChannel
            close $errChannel
            file delete $inputPath $outPath $errPath
            if {$client ne "" && [info object isa object $client]} {
                $client destroy
            }
        }
    }
    set results
} -result [list \
    [list help 0 "Usage: tclsh main.tcl ?task?" ""] \
    [list interactive 0 \
        "OODZ Agent - interactive mode\nType /help for commands.\nyou>" ""] \
    [list success 0 "CLI response" ""] \
    [list failure 1 "" "Error: fake failure"]]

test cli-1.2 {interactive CLI retains context and handles commands} -body {
    set client [::FakeLLMClient new [list \
        "first response" "second response"]]
    set inputChannel [file tempfile inputPath]
    set outChannel [file tempfile outPath]
    set errChannel [file tempfile errPath]

    try {
        foreach line {
            {first task}
            {second task}
            /history
            /new
            /history
            /tools
            /skills
            /unknown
            /exit
        } {
            puts $inputChannel $line
        }
        flush $inputChannel
        seek $inputChannel 0

        set exitCode [::main \
            $projectDir {} $client \
            $outChannel $errChannel $inputChannel]
        flush $outChannel
        flush $errChannel
        seek $outChannel 0
        seek $errChannel 0
        set output [read $outChannel]
        set errors [read $errChannel]
        set calls [$client getCalls]
        set secondMessages [lindex [lindex $calls 1] 1]

        list \
            $exitCode \
            [llength $calls] \
            [dict get [lindex $secondMessages 0] content] \
            [dict get [lindex $secondMessages 1] content] \
            [dict get [lindex $secondMessages 2] content] \
            [expr {[string first "Available skills" \
                [lindex [lindex $calls 0] 0]] >= 0}] \
            [expr {[string first \
                "assistant> second response" $output] >= 0}] \
            [expr {[string first \
                "Started a new conversation." $output] >= 0}] \
            [expr {[string first "(empty)" $output] >= 0}] \
            [expr {
                [string first "fossil_merge" $output] >= 0
                && [string first "read_file" $output] >= 0
                && [string first "xml_validate" $output] >= 0
            }] \
            [expr {[string first \
                "create-oodz-class - Create or modify NX domain classes" \
                $output] >= 0}] \
            [string trim $errors]
    } finally {
        close $inputChannel
        close $outChannel
        close $errChannel
        file delete $inputPath $outPath $errPath
        $client destroy
    }
} -result [list \
    0 2 \
    "first task" "first response" "second task" \
    1 1 1 1 1 1 \
    "Unknown command: /unknown (use /help)"]

test cli-tool-1.1 {interactive tool command bypasses the LLM client} -body {
    set client [::FakeLLMClient new {}]
    set inputChannel [file tempfile inputPath]
    set outChannel [file tempfile outPath]
    set errChannel [file tempfile errPath]

    try {
        puts $inputChannel {/tool list_files {}}
        puts $inputChannel /exit
        flush $inputChannel
        seek $inputChannel 0

        set exitCode [::main \
            $projectDir {} $client \
            $outChannel $errChannel $inputChannel]
        flush $outChannel
        flush $errChannel
        seek $outChannel 0
        seek $errChannel 0
        set output [read $outChannel]
        set errors [read $errChannel]

        list \
            $exitCode \
            [llength [$client getCalls]] \
            [expr {[string length [string trim $output]] > 0}] \
            [string trim $errors]
    } finally {
        close $inputChannel
        close $outChannel
        close $errChannel
        file delete $inputPath $outPath $errPath
        $client destroy
    }
} -result [list 0 0 1 ""]

test cli-multiline-1.1 {multiline mode preserves lines and supports cancellation} -body {
    set client [::FakeLLMClient new [list "multiline response"]]
    set inputChannel [file tempfile inputPath]
    set outChannel [file tempfile outPath]
    set errChannel [file tempfile errPath]

    try {
        foreach line [list \
            /multi \
            {Create an NX class.} \
            {} \
            {  Preserve this indentation.} \
            /send \
            /multi \
            {do not send this} \
            /cancel \
            /exit] {
            puts $inputChannel $line
        }
        flush $inputChannel
        seek $inputChannel 0

        set exitCode [::main \
            $projectDir {} $client \
            $outChannel $errChannel $inputChannel]
        flush $outChannel
        seek $outChannel 0
        set output [read $outChannel]
        set calls [$client getCalls]
        set task [dict get \
            [lindex [lindex [lindex $calls 0] 1] end] content]

        list \
            $exitCode \
            [llength $calls] \
            $task \
            [expr {[string first "Multiline mode:" $output] >= 0}] \
            [expr {[string first "Multiline input cancelled." $output] >= 0}]
    } finally {
        close $inputChannel
        close $outChannel
        close $errChannel
        file delete $inputPath $outPath $errPath
        $client destroy
    }
} -result [list \
    0 1 \
    "Create an NX class.\n\n  Preserve this indentation." \
    1 1]

test cli-translation-1.1 {translation shortcut expands into a native-script task} -body {
    set client [::FakeLLMClient new [list "translation prepared"]]
    set inputChannel [file tempfile inputPath]
    set outChannel [file tempfile outPath]
    set errChannel [file tempfile errPath]

    try {
        puts $inputChannel {/oodz_trns Bottle}
        puts $inputChannel /exit
        flush $inputChannel
        seek $inputChannel 0

        set exitCode [::main \
            $projectDir {} $client \
            $outChannel $errChannel $inputChannel]
        set calls [$client getCalls]
        set task [dict get \
            [lindex [lindex [lindex $calls 0] 1] end] content]

        list \
            $exitCode \
            [llength $calls] \
            [expr {[string first "Bottle" $task] >= 0}] \
            [expr {[string first "Never transliterate" $task] >= 0}]
    } finally {
        close $inputChannel
        close $outChannel
        close $errChannel
        file delete $inputPath $outPath $errPath
        $client destroy
    }
} -result [list 0 1 1 1]

test cli-history-1.1 {interactive history persists and new removes it} -body {
    set directory [file normalize [file join \
        [::tcltest::temporaryDirectory] cli-history-[pid]]]
    file mkdir $directory
    set historyPath [file join $directory history.json]
    set firstClient [::FakeLLMClient new [list "first response"]]
    set secondClient [::FakeLLMClient new [list "second response"]]

    try {
        foreach session {
            {firstClient {{first task} /exit}}
            {secondClient {{second task} /exit}}
            {secondClient {/new /exit}}
        } {
            lassign $session clientName lines
            set inputChannel [file tempfile inputPath]
            set outChannel [file tempfile outPath]
            set errChannel [file tempfile errPath]
            try {
                foreach line $lines {
                    puts $inputChannel $line
                }
                flush $inputChannel
                seek $inputChannel 0
                ::main $projectDir {} [set $clientName] \
                    $outChannel $errChannel $inputChannel $historyPath
            } finally {
                close $inputChannel
                close $outChannel
                close $errChannel
                file delete $inputPath $outPath $errPath
            }
        }

        set secondMessages [lindex \
            [lindex [$secondClient getCalls] 0] 1]
        list \
            [lmap message $secondMessages {
                dict get $message content
            }] \
            [file exists $historyPath]
    } finally {
        $firstClient destroy
        $secondClient destroy
        file delete -force $directory
    }
} -result [list \
    [list "first task" "first response" "second task"] \
    0]

test client-api-key-1.1 {client requires API key from configuration} -body {
    set missingConfig [::FakeConfig new]
    set presentConfig [::FakeConfig new [dict create \
        LLM.api_key "test-only-key"]]
    try {
        set missingResult [catch {
            ::tLLMClient new $missingConfig
        } missingMessage]

        set client [::tLLMClient new $presentConfig]
        set presentResult [info object isa object $client]
        $client destroy

        list $missingResult $missingMessage $presentResult
    } finally {
        $missingConfig destroy
        $presentConfig destroy
    }
} -result [list 1 "LLM.api_key is required in conf/conf.ini" 1]

test client-ollama-1.1 {Ollama works without authorization or DeepSeek fields} -body {
    set config [::FakeConfig new [dict create \
        LLM.provider ollama \
        LLM.api_key "" \
        LLM.model qwen3 \
        LLM.url http://localhost:11434/v1/chat/completions \
        LLM.max_retries 0]]
    set responseBody [::json::write object \
        choices [::json::write array \
            [::json::write object message [::json::write object \
                role [::json::write string assistant] \
                content [::json::write string "local response"]]]]]
    set transport [::FakeTransport new [list \
        [dict create status ok code 200 body $responseBody]]]
    set client [::tLLMClient new $config $transport]
    try {
        set result [$client queryMessage "system" [list \
            [dict create role user content hello]] [list \
            [dict create name read_file description "Read a file" \
                parameters_json {{"type":"object"}}]]]
        set request [lindex [$transport getRequests] 0]
        set payload [::json::json2dict [lindex $request 1]]
        list \
            [dict get $result content] \
            [lindex $request 2] \
            [dict get $payload model] \
            [dict exists $payload tools] \
            [dict exists $payload thinking] \
            [dict exists $payload parallel_tool_calls]
    } finally {
        $client destroy
        $transport destroy
        $config destroy
    }
} -result [list "local response" {} qwen3 1 0 0]

test client-tls-1.1 {TLS registration uses supported option names} -body {
    set sourceChannel [open [file join $projectDir clientClass.tcl] r]
    try {
        set clientSource [read $sourceChannel]
    } finally {
        close $sourceChannel
    }

    list \
        [expr {[string first "-tls1.2 1" $clientSource] >= 0}] \
        [expr {[string first "-tls1.3 1" $clientSource] >= 0}] \
        [expr {[string first "-tls1_2" $clientSource] < 0}] \
        [expr {[string first "-tls1_3" $clientSource] < 0}]
} -result [list 1 1 1 1]

test client-http-encoding-1.1 {HTTP request bodies are explicitly UTF-8} -body {
    set sourceChannel [open [file join $projectDir clientClass.tcl] r]
    try {
        set clientSource [read $sourceChannel]
    } finally {
        close $sourceChannel
    }
    list \
        [regexp -all -- \
            {-query \[encoding convertto utf-8 \$payload\]} \
            $clientSource] \
        [expr {[string first \
            {body [encoding convertfrom utf-8 [::http::data $token]]} \
            $clientSource] >= 0}]
} -result [list 2 1]

test client-json-1.1 {JSON payload and response preserve message content} -body {
    set config [::FakeConfig new [dict create \
        LLM.api_key "test-only-key" \
        LLM.model "deepseek-v4-flash"]]
    set client [::tLLMClient new $config]
    set special "quote \" backslash \\ newline\n tab\t café \u263a"

    try {
        set payload [::json::json2dict \
            [$client buildPayload "System: $special" [list \
                [dict create role user content "User: $special"]]]]
        set responseBody [::json::write object \
            choices [::json::write array \
                [::json::write object \
                    message [::json::write object \
                        role [::json::write string "assistant"] \
                        content [::json::write string $special]]]]]

        list \
            [dict get $payload model] \
            [dict get [lindex [dict get $payload messages] 0] content] \
            [dict get [lindex [dict get $payload messages] 1] content] \
            [$client parseResponse $responseBody]
    } finally {
        $client destroy
        $config destroy
    }
} -result [list \
    "deepseek-v4-flash" \
    "System: quote \" backslash \\ newline\n tab\t café \u263a" \
    "User: quote \" backslash \\ newline\n tab\t café \u263a" \
    "quote \" backslash \\ newline\n tab\t café \u263a"]

test client-json-1.2 {JSON parser reports malformed and API error bodies} -body {
    set config [::FakeConfig new [dict create LLM.api_key "test-only-key"]]
    set client [::tLLMClient new $config]

    try {
        set malformedBody "[format %c 123]not JSON"
        set malformedCode [catch {
            $client parseResponse $malformedBody
        } malformedMessage]
        set apiErrorCode [catch {
            $client parseResponse {{"error":{"message":"bad request"}}}
        } apiErrorMessage]

        list \
            $malformedCode $malformedMessage \
            $apiErrorCode $apiErrorMessage
    } finally {
        $client destroy
        $config destroy
    }
} -result [list \
    1 "Parsing Error: invalid JSON response" \
    1 "Parsing Error: response has no assistant message"]

test client-json-1.3 {DeepSeek tool-call messages round-trip without field loss} -body {
    set config [::FakeConfig new [dict create LLM.api_key "test-only-key"]]
    set client [::tLLMClient new $config]
    set arguments [::json::write object \
        path [::json::write string "main.tcl"]]
    set assistantMessage [dict create \
        role assistant \
        content "" \
        reasoning_content "I need to inspect the file." \
        tool_calls [list [dict create \
            id "call_1" \
            type "function" \
            function [dict create \
                name "read_file" \
                arguments $arguments]]]]
    set toolMessage [dict create \
        role tool \
        content "file contents" \
        tool_call_id "call_1"]

    try {
        set responseBody [::json::write object \
            choices [::json::write array \
                [::json::write object \
                    message [$client encodeMessage $assistantMessage]]]]
        set parsedMessage [$client parseResponseMessage $responseBody]
        set payload [::json::json2dict \
            [$client buildPayload "system" [list \
                [dict create role user content "inspect main.tcl"] \
                $parsedMessage \
                $toolMessage]]]
        set parsedCall [lindex [dict get $parsedMessage tool_calls] 0]
        set encodedAssistant [lindex [dict get $payload messages] 2]
        set encodedTool [lindex [dict get $payload messages] 3]

        list \
            [dict get $parsedMessage role] \
            [dict get $parsedMessage content] \
            [dict get $parsedMessage reasoning_content] \
            [dict get $parsedCall id] \
            [dict get $parsedCall function name] \
            [::json::json2dict [dict get $parsedCall function arguments]] \
            [dict get $encodedAssistant content] \
            [dict get $encodedAssistant reasoning_content] \
            [::json::json2dict [dict get \
                [lindex [dict get $encodedAssistant tool_calls] 0] \
                function arguments]] \
            [dict get $encodedTool tool_call_id] \
            [dict get $encodedTool content]
    } finally {
        $client destroy
        $config destroy
    }
} -result [list \
    "assistant" \
    "" \
    "I need to inspect the file." \
    "call_1" \
    "read_file" \
    [dict create path "main.tcl"] \
    "" \
    "I need to inspect the file." \
    [dict create path "main.tcl"] \
    "call_1" \
    "file contents"]

test client-json-1.4 {DeepSeek payload includes plugin tool definitions} -body {
    set config [::FakeConfig new [dict create LLM.api_key "test-only-key"]]
    set registry [::tPluginRegistry new \
        $projectDir [list [file join $projectDir plugins]]]
    set client [::tLLMClient new $config]

    try {
        set payload [::json::json2dict \
            [$client buildPayload "system" [list \
                [dict create role user content "inspect files"]] \
                [$registry definitions]]]
        set tools [dict get $payload tools]
        set readFile {}
        foreach tool $tools {
            if {[dict get $tool function name] eq "read_file"} {
                set readFile $tool
                break
            }
        }

        list \
            [llength $tools] \
            [dict get $payload parallel_tool_calls] \
            [dict get $payload thinking type] \
            [dict get [lindex $tools 0] type] \
            [dict get $readFile function name] \
            [dict get $readFile function parameters type] \
            [dict get $readFile function parameters required]
    } finally {
        $client destroy
        $registry destroy
        $config destroy
    }
} -result [list 47 false disabled function read_file object [list path]]

test client-stream-1.1 {streaming assembles content and tool-call deltas} -body {
    set config [::FakeConfig new [dict create LLM.api_key "test-only-key"]]
    set events [list \
        [::json::write object choices [::json::write array \
            [::json::write object delta [::json::write object \
                reasoning_content [::json::write string "Need a file. "]]]]] \
        [::json::write object choices [::json::write array \
            [::json::write object delta [::json::write object \
                content [::json::write string "Checking..."]]]]] \
        [::json::write object choices [::json::write array \
            [::json::write object delta [::json::write object \
                tool_calls [::json::write array \
                    [::json::write object \
                        index 0 \
                        id [::json::write string "call_"] \
                        type [::json::write string "function"] \
                        function [::json::write object \
                            name [::json::write string "read_"] \
                            arguments [::json::write string \
                                "{\"path\":"]]]]]]]] \
        [::json::write object choices [::json::write array \
            [::json::write object delta [::json::write object \
                tool_calls [::json::write array \
                    [::json::write object \
                        index 0 \
                        id [::json::write string "1"] \
                        function [::json::write object \
                            name [::json::write string "file"] \
                            arguments [::json::write string \
                                "\"main.tcl\"}"]]]]]]]]]
    set transport [::FakeStreamingTransport new $events]
    set client [::tLLMClient new $config $transport]
    set ::StreamCapture::content ""

    try {
        set message [$client queryMessageStream \
            "system" \
            [list [dict create role user content "inspect"]] \
            {} \
            [list ::StreamCapture::append]]
        set call [lindex [dict get $message tool_calls] 0]
        set payload [::json::json2dict [$transport getPayload]]

        list \
            [dict get $payload stream] \
            $::StreamCapture::content \
            [dict get $message content] \
            [dict get $message reasoning_content] \
            [dict get $call id] \
            [dict get $call type] \
            [dict get $call function name] \
            [::json::json2dict [dict get $call function arguments]]
    } finally {
        $client destroy
        $transport destroy
        $config destroy
    }
} -result [list \
    true \
    "Checking..." \
    "Checking..." \
    "Need a file. " \
    "call_1" \
    "function" \
    "read_file" \
    [dict create path main.tcl]]

test client-stream-1.2 {empty stream falls back to a visible buffered response} -body {
    set config [::FakeConfig new [dict create \
        LLM.api_key "test-only-key" \
        LLM.max_retries 0]]
    set fallbackBody [::json::write object \
        choices [::json::write array [::json::write object \
            message [::json::write object \
                role [::json::write string assistant] \
                content [::json::write string "Olá!"]]]]]
    set transport [::FakeStreamingTransport new {} $fallbackBody]
    set client [::tLLMClient new $config $transport]
    set ::StreamCapture::content ""

    try {
        set message [$client queryMessageStream \
            "system" [list [dict create role user content "ola"]] {} \
            [list ::StreamCapture::append]]
        list \
            [dict get $message content] \
            $::StreamCapture::content \
            [$transport getPostCount]
    } finally {
        $client destroy
        $transport destroy
        $config destroy
    }
} -result [list "Olá!" "Olá!" 1]

test client-stream-1.3 {timed-out empty stream falls back to buffered request} -body {
    set config [::FakeConfig new [dict create \
        LLM.api_key "test-only-key" \
        LLM.max_retries 0]]
    set fallbackBody [::json::write object \
        choices [::json::write array [::json::write object \
            message [::json::write object \
                role [::json::write string assistant] \
                content [::json::write string "Recovered response"]]]]]
    set transport [::FakeStreamingTransport new {} $fallbackBody \
        [dict create status timeout code 200 body ""]]
    set client [::tLLMClient new $config $transport]
    set ::StreamCapture::content ""

    try {
        set message [$client queryMessageStream \
            "system" [list [dict create role user content "create file"]] {} \
            [list ::StreamCapture::append]]
        list \
            [dict get $message content] \
            $::StreamCapture::content \
            [$transport getPostCount]
    } finally {
        $client destroy
        $transport destroy
        $config destroy
    }
} -result [list "Recovered response" "Recovered response" 1]

test client-stream-1.4 {rejected empty stream falls back to buffered request} -body {
    set config [::FakeConfig new [dict create \
        LLM.api_key "test-only-key" \
        LLM.max_retries 0]]
    set fallbackBody [::json::write object \
        choices [::json::write array [::json::write object \
            message [::json::write object \
                role [::json::write string assistant] \
                content [::json::write string "Buffered recovery"]]]]]
    set transport [::FakeStreamingTransport new {} $fallbackBody \
        [dict create status ok code 400 body ""]]
    set client [::tLLMClient new $config $transport]
    set ::StreamCapture::content ""

    try {
        set message [$client queryMessageStream \
            "system" [list [dict create role user content "inspect"]] {} \
            [list ::StreamCapture::append]]
        list \
            [dict get $message content] \
            $::StreamCapture::content \
            [$transport getPostCount]
    } finally {
        $client destroy
        $transport destroy
        $config destroy
    }
} -result [list "Buffered recovery" "Buffered recovery" 1]

test client-stream-1.5 {stream socket exception falls back with retries} -body {
    set config [::FakeConfig new [dict create \
        LLM.api_key "test-only-key" \
        LLM.max_retries 0]]
    set fallbackBody [::json::write object \
        choices [::json::write array [::json::write object \
            message [::json::write object \
                role [::json::write string assistant] \
                content [::json::write string "Recovered from DNS"]]]]]
    set transport [::FakeStreamingTransport new \
        {} $fallbackBody "" "mock DNS failure"]
    set client [::tLLMClient new $config $transport]
    set ::StreamCapture::content ""
    try {
        set message [$client queryMessageStream \
            system [list [dict create role user content continue]] {} \
            [list ::StreamCapture::append]]
        list [dict get $message content] \
            $::StreamCapture::content [$transport getPostCount]
    } finally {
        $client destroy
        $transport destroy
        $config destroy
    }
} -result [list "Recovered from DNS" "Recovered from DNS" 1]

test client-stream-1.6 {SSE transport decodes complete UTF-8 events} -body {
    set transport [::tHttpTransport new]
    set channel [file tempfile ssePath]
    set event [format {{"text":"%s"}} "café — Tcl"]
    set ::SSECapture::events {}

    try {
        fconfigure $channel -translation binary
        puts -nonewline $channel [encoding convertto utf-8 \
            "data: $event\n\ndata: \[DONE\]\n\n"]
        flush $channel
        seek $channel 0

        set bytesRead [$transport receiveStream \
            [list ::SSECapture::add] $channel token]
        list \
            [expr {$bytesRead > 0}] \
            [llength $::SSECapture::events] \
            [dict get [::json::json2dict \
                [lindex $::SSECapture::events 0]] text]
    } finally {
        close $channel
        file delete $ssePath
        $transport destroy
    }
} -result [list 1 1 "café — Tcl"]

test client-config-1.1 {client validates HTTP configuration} -body {
    set cases [list \
        [dict create LLM.api_key key LLM.provider other] \
        [dict create LLM.api_key key LLM.model ""] \
        [dict create LLM.api_key key LLM.url "https://example.com"] \
        [dict create LLM.api_key key LLM.timeout "later"] \
        [dict create LLM.api_key key LLM.max_retries -1] \
        [dict create LLM.api_key key LLM.retry_delay_ms 0] \
        [dict create LLM.api_key key LLM.thinking perhaps]]
    set results {}

    foreach values $cases {
        set config [::FakeConfig new $values]
        lappend results [catch {
            ::tLLMClient new $config
        } message] $message
        $config destroy
    }
    set results
} -result [list \
    1 "LLM.provider must be one of: deepseek, ollama" \
    1 "LLM.model must not be empty" \
    1 "LLM.url must be a full HTTP endpoint" \
    1 "LLM.timeout must be a positive integer" \
    1 "LLM.max_retries must be a non-negative integer" \
    1 "LLM.retry_delay_ms must be a positive integer" \
    1 "LLM.thinking must be boolean"]

test client-http-1.1 {HTTP outcomes are handled through injected transport} -body {
    set config [::FakeConfig new [dict create \
        LLM.api_key "test-only-key" \
        LLM.url "https://example.test/v1/chat/completions" \
        LLM.max_retries 0]]
    set successBody [::json::write object \
        choices [::json::write array \
            [::json::write object \
                message [::json::write object \
                    role [::json::write string "assistant"] \
                    content [::json::write string "success"]]]]]
    set errorBody [::json::write object \
        error [::json::write object \
            message [::json::write string "rate limited"]]]
    set transport [::FakeTransport new [list \
        [dict create status ok code 200 body $successBody] \
        [dict create status ok code 429 body $errorBody] \
        [dict create status ok code 200 body "invalid JSON"] \
        [dict create error "mock timeout"]]]
    set client [::tLLMClient new $config $transport]

    try {
        set successResult [$client query "system" [list \
            [dict create role user content "user"]]]

        set httpErrorResult [catch {
            $client query "system" [list \
                [dict create role user content "user"]]
        } errorMessage]

        set malformedCode [catch {
            $client query "system" [list \
                [dict create role user content "user"]]
        } malformedMessage]

        set timeoutCode [catch {
            $client query "system" [list \
                [dict create role user content "user"]]
        } timeoutMessage]

        list \
            $successResult \
            $httpErrorResult $errorMessage \
            $malformedCode $malformedMessage \
            $timeoutCode $timeoutMessage \
            [llength [$transport getRequests]]
    } finally {
        $client destroy
        $transport destroy
        $config destroy
    }
} -result [list \
    "success" \
    1 "DeepSeek API Error: HTTP 429: rate limited" \
    1 "Parsing Error: invalid JSON response" \
    1 "mock timeout" \
    4]

test client-retry-1.1 {transient failures retry with bounded backoff} -body {
    set config [::FakeConfig new [dict create \
        LLM.api_key "test-only-key" \
        LLM.url "https://example.test/v1/chat/completions" \
        LLM.max_retries 2 \
        LLM.retry_delay_ms 100]]
    set successBody [::json::write object \
        choices [::json::write array \
            [::json::write object \
                message [::json::write object \
                    role [::json::write string "assistant"] \
                    content [::json::write string "recovered"]]]]]
    set transport [::FakeTransport new [list \
        [dict create status ok code 503 body "unavailable"] \
        [dict create error "connection reset"] \
        [dict create status ok code 200 body $successBody]]]
    set client [::tLLMClient new $config $transport]

    try {
        list \
            [$client query "system" [list \
                [dict create role user content "user"]]] \
            [llength [$transport getRequests]] \
            [$transport getWaits]
    } finally {
        $client destroy
        $transport destroy
        $config destroy
    }
} -result [list "recovered" 3 [list 100 200]]

test client-retry-1.2 {non-transient and parsing errors do not retry} -body {
    set config [::FakeConfig new [dict create \
        LLM.api_key "test-only-key" \
        LLM.url "https://example.test/v1/chat/completions" \
        LLM.max_retries 2]]
    set authBody [::json::write object \
        error [::json::write object \
            message [::json::write string "unauthorized"]]]
    set transport [::FakeTransport new [list \
        [dict create status ok code 401 body $authBody] \
        [dict create status ok code 200 body "invalid JSON"]]]
    set client [::tLLMClient new $config $transport]

    try {
        set authResult [catch {
            $client query "system" [list \
                [dict create role user content "user"]]
        } authMessage]
        set parseResult [catch {
            $client query "system" [list \
                [dict create role user content "user"]]
        } parseMessage]
        list \
            $authResult $authMessage \
            $parseResult $parseMessage \
            [llength [$transport getRequests]] \
            [$transport getWaits]
    } finally {
        $client destroy
        $transport destroy
        $config destroy
    }
} -result [list \
    1 "DeepSeek API Error: HTTP 401: unauthorized" \
    1 "Parsing Error: invalid JSON response" \
    2 {}]

set failedCount $::tcltest::numTests(Failed)
cleanupTests

if {$failedCount > 0} {
    exit 1
}
