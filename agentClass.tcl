# ====================================================================
# Class 2: The Agent (Handles identity, goals, and thinking cycle)
# ====================================================================
::oo::class create tAgent {
    variable log name systemRole llmClient memory pluginRegistry maxIterations
    variable streamCallback maxHistoryMessages maxHistoryChars historySummary
    variable summarizedMessageCount summarizeHistoryEnabled
    variable cancelRequested diagnostics

    constructor {
        agentName role clientObject {registryObject ""} {iterationLimit 8}
        {configuredStreamCallback ""} {configuredMaxHistoryMessages 200}
        {configuredSummarizeHistory true} {configuredMaxHistoryChars 120000}
    } {
        set log [::tLogger getLogger [self class]]
        set name $agentName
        set systemRole $role
        set llmClient $clientObject
        set pluginRegistry $registryObject
        if {![string is entier -strict $iterationLimit] || $iterationLimit <= 0} {
            error "Agent iteration limit must be a positive integer"
        }
        set maxIterations $iterationLimit
        if {![string is entier -strict $configuredMaxHistoryMessages]
                || $configuredMaxHistoryMessages <= 0} {
            error "Agent history limit must be a positive integer"
        }
        set maxHistoryMessages $configuredMaxHistoryMessages
        if {![string is entier -strict $configuredMaxHistoryChars]
                || $configuredMaxHistoryChars <= 0} {
            error "Agent history character limit must be a positive integer"
        }
        set maxHistoryChars $configuredMaxHistoryChars
        if {![string is boolean -strict $configuredSummarizeHistory]} {
            error "Agent summarize_history must be boolean"
        }
        set summarizeHistoryEnabled [expr {$configuredSummarizeHistory ? 1 : 0}]
        set streamCallback $configuredStreamCallback
        set memory [list] ;# Simple list to track conversation history
        set historySummary ""
        set summarizedMessageCount 0
        set cancelRequested 0
        set diagnostics ""

        $log log info "Agent '$name' successfully spawned."
    }

    method run {task} {
        set cancelRequested 0
        if {"beginRequest" in [info object methods $llmClient -all]} {
            $llmClient beginRequest
        }
        $log log info "Agent execution triggered for task: '$task'"
        my diagnostic task_start [dict create task_chars [string length $task]]
        set response ""
        set userMessage [dict create role user content $task]
        set requestHistory [my requestHistory]
        set requestMessages [concat $requestHistory [list $userMessage]]

        if {[catch {
            if {$pluginRegistry eq ""} {
                set response [$llmClient query $systemRole $requestMessages]
                set requestMessages [concat $requestMessages [list \
                    [dict create role assistant content $response]]]
            } else {
                set response [my runAgentLoop requestMessages]
                set requestMessages [dict get $response messages]
                set response [dict get $response content]
            }
        } errMsg errOptions]} {
            $log log critical "Agent run failed: $errMsg"
            my diagnostic task_error
            if {[dict exists $errOptions -errorcode]
                    && [dict get $errOptions -errorcode] eq {OODZ CANCELLED}} {
                lappend requestMessages [dict create role assistant content \
                    "Request stopped by user."]
                set newMessages [lrange $requestMessages \
                    [llength $requestHistory] end]
                set memory [concat $memory $newMessages]
                return -options $errOptions $errMsg
            }
            lappend requestMessages [dict create role assistant content \
                "The previous task ended before a final response: $errMsg"]
            set newMessages [lrange $requestMessages \
                [llength $requestHistory] end]
            set memory [concat $memory $newMessages]
            return -options $errOptions $errMsg
        }

        set newMessages [lrange $requestMessages \
            [llength $requestHistory] end]
        set memory [concat $memory $newMessages]
        $log log info "Thinking cycle completed successfully."
        my diagnostic task_complete
        return $response
    }

    method setDiagnostics {collector} {
        set diagnostics $collector
    }

    method diagnostic {type {details {}}} {
        if {$diagnostics ne ""} {$diagnostics record $type $details}
    }

    method runAgentLoop {messagesVariable} {
        upvar 1 $messagesVariable messages
        set previousToolFingerprint ""
        for {set iteration 1} {$iteration <= $maxIterations} {incr iteration} {
            my checkCancelled
            my diagnostic iteration [dict create number $iteration]
            # Plugin discovery may activate additional definitions between
            # model turns, so take a fresh snapshot on every iteration.
            set tools [$pluginRegistry definitions]
            set activeMessages [my boundedModelMessages \
                [dict get [my messageWindow $messages] included]]
            if {$streamCallback ne "" && "queryMessageStream" in [info object methods $llmClient -all]} {
                set assistantMessage [$llmClient queryMessageStream $systemRole $activeMessages $tools $streamCallback]
                {*}$streamCallback "\n"
            } else {
                set assistantMessage [$llmClient queryMessage $systemRole $activeMessages $tools]
            }
            my checkCancelled

            if {[dict getdef $assistantMessage finish_reason ""] eq "length"} {
                lappend messages $assistantMessage
                my diagnostic response_truncated [dict create reason length]
                return -code error -errorcode {OODZ TRUNCATED} \
                    "Model response was truncated because its output token limit was reached"
            }

            if {![dict exists $assistantMessage tool_calls] || [llength [dict get $assistantMessage tool_calls]] == 0} {
                lappend messages $assistantMessage
                if {![dict exists $assistantMessage content] || [string trim [dict get $assistantMessage content]] eq ""} {
                    error "Agent returned neither tool calls nor final content"
                }
                return [dict create content [dict get $assistantMessage content] messages $messages]
            }

            lappend messages $assistantMessage
            set toolCalls [dict get $assistantMessage tool_calls]
            set toolIndex 0
            foreach toolCall $toolCalls {
                set callId [dict get $toolCall id]
                set function [dict get $toolCall function]
                set toolName [dict get $function name]
                set arguments [dict get $function arguments]
                incr toolIndex

                if {$toolIndex > 1} {
                    set toolResult "Plugin call skipped: OODZ executes at most one tool per model response. Request this tool again in the next response if it is still needed."
                    $log log warn "Skipped extra plugin call: $toolName"
                    my diagnostic tool_skipped [dict create name $toolName reason extra]
                    lappend messages [dict create role tool \
                        content $toolResult tool_call_id $callId]
                    continue
                }

                set fingerprint [list $toolName $arguments]
                if {$fingerprint eq $previousToolFingerprint} {
                    set toolResult "Repeated identical plugin call skipped. Use the previous result or change the arguments."
                    $log log warn "Skipped repeated identical plugin call: $toolName"
                    my diagnostic tool_skipped [dict create name $toolName reason repeated]
                    lappend messages [dict create role tool \
                        content $toolResult tool_call_id $callId]
                    continue
                }
                set previousToolFingerprint $fingerprint
                set started [clock milliseconds]
                $log log info "Executing plugin: $toolName (arguments_chars=[string length $arguments])"
                my diagnostic tool_call [dict create name $toolName \
                    arguments_chars [string length $arguments]]

                set succeeded 1
                if {[catch {
                    $pluginRegistry invokeForModel $toolName $arguments
                } toolResult]} {
                    set succeeded 0
                    set toolResult "Plugin error: $toolResult"
                    $log log warn "Plugin failed: $toolName: $toolResult"
                    my diagnostic tool_failure [dict create name $toolName]
                }
                set duration [expr {[clock milliseconds] - $started}]
                $log log info "Plugin completed: $toolName (success=$succeeded duration_ms=$duration result_chars=[string length $toolResult])"
                my diagnostic tool_result [dict create name $toolName \
                    success $succeeded duration_ms $duration \
                    result_chars [string length $toolResult]]
                lappend messages [dict create role tool content $toolResult tool_call_id $callId]
            }
        }

        set content "Reached the per-request work limit of $maxIterations model iterations. Completed changes have been preserved. Review the reported changes, then say 'next' to continue."
        lappend messages [dict create role assistant content $content]
        $log log warn "Agent reached maximum iterations: $maxIterations"
        my diagnostic iteration_limit [dict create limit $maxIterations]
        return [dict create content $content messages $messages]
    }

    method cancel {} {
        set cancelRequested 1
        if {"cancel" in [info object methods $llmClient -all]} {
            $llmClient cancel
        }
        if {$pluginRegistry ne ""
                && "cancel" in [info object methods $pluginRegistry -all]} {
            $pluginRegistry cancel
        }
        return
    }

    method checkCancelled {} {
        if {$cancelRequested} {
            return -code error -errorcode {OODZ CANCELLED} \
                "Request stopped by user"
        }
    }


    method getHistory {} {
        return $memory
    }

    method configureSystemRole {role} {
        set systemRole $role
        return
    }

    method requestHistory {} {
        set window [my historyWindow]
        if {$summarizeHistoryEnabled} {
            my compactExcludedHistory [dict get $window excluded]
        }
        set included [dict get $window included]
        if {$historySummary ne ""} {
            set summaryMessage [dict create role system content "Conversation context compacted from older turns:\n$historySummary"]
            set included [linsert $included 0 $summaryMessage]
        }
        return $included
    }

    method historyWindow {} {
        return [my messageWindow $memory]
    }

    method messageWindow {sourceMessages} {
        set prefix {}
        while {[llength $sourceMessages] > 0
                && [dict exists [lindex $sourceMessages 0] role]
                && [dict get [lindex $sourceMessages 0] role] eq "system"} {
            lappend prefix [lindex $sourceMessages 0]
            set sourceMessages [lrange $sourceMessages 1 end]
        }
        set turns {}
        set currentTurn {}
        foreach message $sourceMessages {
            if {[dict exists $message role] && [dict get $message role] eq "user" && [llength $currentTurn] > 0} {
                lappend turns $currentTurn
                set currentTurn {}
            }
            lappend currentTurn $message
        }
        if {[llength $currentTurn] > 0} {
            lappend turns $currentTurn
        }

        set selected {}
        # System-prefix messages, including the persisted conversation summary,
        # consume the same request budget as ordinary history. Ignoring them can
        # produce an oversized intermediate window that boundedModelMessages
        # resolves by retaining only the newest user message.
        set selectedCount [llength $prefix]
        set selectedChars [my messagesSize $prefix]
        for {set index [expr {[llength $turns] - 1}]} {$index >= 0} {incr index -1} {
            set turn [lindex $turns $index]
            set turnSize [llength $turn]
            set turnChars [my messagesSize $turn]
            if {$selectedCount > 0
                    && ($selectedCount + $turnSize > $maxHistoryMessages
                        || $selectedChars + $turnChars > $maxHistoryChars)} {
                break
            }
            set selected [concat $turn $selected]
            incr selectedCount $turnSize
            incr selectedChars $turnChars
            if {$selectedCount >= $maxHistoryMessages
                    || $selectedChars >= $maxHistoryChars} {
                break
            }
        }
        set excludedCount [expr {[llength $sourceMessages] - [llength $selected]}]
        return [dict create included [concat $prefix $selected] \
            excluded [lrange $sourceMessages 0 [expr {$excludedCount - 1}]]]
    }

    method messagesSize {messages} {
        set size 0
        foreach message $messages {
            foreach field {content reasoning_content tool_call_id} {
                if {[dict exists $message $field]} {
                    incr size [string length [dict get $message $field]]
                }
            }
            if {[dict exists $message tool_calls]} {
                incr size [string length [dict get $message tool_calls]]
            }
            incr size 32
        }
        return $size
    }

    method compactModelMessage {message} {
        set role [dict getdef $message role ""]
        set toolContentLimit [expr {max(200, min(6000, $maxHistoryChars / 3))}]
        if {$role eq "tool" && [dict exists $message content]
                && [string length [dict get $message content]] > $toolContentLimit} {
            dict set message content \
                "[string range [dict get $message content] 0 [expr {$toolContentLimit - 2}]]…\n\[Tool result truncated in active context.\]"
        }
        if {$role eq "assistant" && [dict exists $message reasoning_content]
                && [string length [dict get $message reasoning_content]] > 2000} {
            dict set message reasoning_content \
                "[string range [dict get $message reasoning_content] 0 1998]…"
        }
        if {$role eq "assistant" && [dict exists $message content]
                && [string length [dict get $message content]] > 4000} {
            dict set message content \
                "[string range [dict get $message content] 0 3998]…"
        }
        if {$role eq "assistant" && [dict exists $message tool_calls]} {
            set compactCalls {}
            foreach call [dict get $message tool_calls] {
                if {[dict exists $call function arguments]
                        && [string length [dict get $call function arguments]] > 6000} {
                    dict set call function arguments \
                        {{"context_omitted":true}}
                }
                lappend compactCalls $call
            }
            dict set message tool_calls $compactCalls
        }
        return $message
    }

    method boundedModelMessages {messages} {
        if {[my messagesSize $messages] <= $maxHistoryChars} {
            return $messages
        }

        set userIndex -1
        for {set index [expr {[llength $messages] - 1}]} {$index >= 0} \
                {incr index -1} {
            if {[dict getdef [lindex $messages $index] role ""] eq "user"} {
                set userIndex $index
                break
            }
        }
        if {$userIndex < 0} {
            return [lrange $messages end-[expr {$maxHistoryMessages - 1}] end]
        }

        set userMessage [my compactModelMessage [lindex $messages $userIndex]]
        set groups {}
        set group {}
        foreach message [lrange $messages [expr {$userIndex + 1}] end] {
            set message [my compactModelMessage $message]
            if {[dict getdef $message role ""] eq "assistant"
                    && [llength $group] > 0} {
                lappend groups $group
                set group {}
            }
            lappend group $message
        }
        if {[llength $group] > 0} {
            lappend groups $group
        }

        set selected {}
        set selectedSize [my messagesSize [list $userMessage]]
        for {set index [expr {[llength $groups] - 1}]} {$index >= 0} \
                {incr index -1} {
            set candidate [lindex $groups $index]
            set candidateSize [my messagesSize $candidate]
            if {[llength $selected] > 0
                    && $selectedSize + $candidateSize > $maxHistoryChars} {
                break
            }
            set selected [concat $candidate $selected]
            incr selectedSize $candidateSize
        }

        set omitted [expr {[llength $groups] - 1}]
        if {[llength $selected] > 0} {
            # Count selected assistant/tool groups, not individual messages.
            set selectedFirstRole [dict getdef [lindex $selected 0] role ""]
            set omitted 0
            set selectedGroups 0
            foreach message $selected {
                if {[dict getdef $message role ""] eq "assistant"} {
                    incr selectedGroups
                }
            }
            set omitted [expr {[llength $groups] - $selectedGroups}]
        }
        if {$omitted <= 0} {
            return [concat [list $userMessage] $selected]
        }
        set notice [dict create role system content \
            "Earlier tool exchanges from this same task were omitted to keep the model request bounded. Continue from the latest results and do not repeat completed inspection or edits."]
        $log log info "Compacted active task context: omitted_groups=$omitted"
        my diagnostic context_compaction [dict create omitted_groups $omitted]
        return [concat [list $notice $userMessage] $selected]
    }

    method compactExcerpt {text maximum} {
        set text [string trim $text]
        regsub -all {\s+} $text { } text
        if {[string length $text] <= $maximum} {
            return $text
        }
        return "[string range $text 0 [expr {$maximum - 2}]]…"
    }

    method summarizeMessages {messages} {
        set lines {}
        set tools {}
        foreach message $messages {
            set role [dict get $message role]
            if {$role eq "user" && [dict exists $message content]} {
                lappend lines "User: [my compactExcerpt [dict get $message content] 800]"
            } elseif {$role eq "assistant"} {
                if {[dict exists $message tool_calls]} {
                    foreach call [dict get $message tool_calls] {
                        if {[dict exists $call function name]} {
                            set tool [dict get $call function name]
                            if {$tool ni $tools} {lappend tools $tool}
                        }
                    }
                }
                if {[dict exists $message content]
                        && [string trim [dict get $message content]] ne ""} {
                    lappend lines "Assistant: [my compactExcerpt [dict get $message content] 1200]"
                }
            }
        }
        if {[llength $tools] > 0} {
            lappend lines "Tools used: [join $tools {, }]"
        }
        return [join $lines "\n"]
    }

    method compactExcludedHistory {excluded} {
        set excludedCount [llength $excluded]
        if {$excludedCount <= $summarizedMessageCount} {
            return
        }
        set newMessages [lrange $excluded $summarizedMessageCount end]
        set addition [my summarizeMessages $newMessages]
        if {$addition ne ""} {
            if {$historySummary ne ""} {append historySummary "\n\n"}
            append historySummary $addition
            if {[string length $historySummary] > 24000} {
                set historySummary "…older compacted context omitted…\n[string range $historySummary end-22999 end]"
            }
        }
        set summarizedMessageCount $excludedCount
    }

    method getExcludedHistory {} {
        return [dict get [my historyWindow] excluded]
    }

    method replaceHistory {messages} {
        set memory $messages
        set historySummary ""
        set summarizedMessageCount 0
        return
    }

    method replaceHistoryState {state} {
        foreach field {messages summary summarized_messages} {
            if {![dict exists $state $field]} {
                error "Conversation state is missing '$field'"
            }
        }
        set count [dict get $state summarized_messages]
        set messages [dict get $state messages]
        if {![string is entier -strict $count] || $count < 0 || $count > [llength $messages]} {
            error "Invalid summarized message count"
        }
        set memory $messages
        set historySummary [dict get $state summary]
        set summarizedMessageCount $count
        return
    }

    method getHistoryState {} {
        return [dict create messages $memory summary $historySummary summarized_messages $summarizedMessageCount]
    }

    method summarizesHistory {} {
        return $summarizeHistoryEnabled
    }

    method clearHistory {} {
        set memory {}
        set historySummary ""
        set summarizedMessageCount 0
        return
    }

    method usesStreaming {} {
        expr {$streamCallback ne ""}
    }
}
