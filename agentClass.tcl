# ====================================================================
# Class 2: The Agent (Handles identity, goals, and thinking cycle)
# ====================================================================
::oo::class create tAgent {
    variable log name systemRole llmClient memory pluginRegistry maxIterations
    variable streamCallback maxHistoryMessages historySummary
    variable summarizedMessageCount summarizeHistoryEnabled

    constructor {
        agentName role clientObject {registryObject ""} {iterationLimit 8}
        {configuredStreamCallback ""} {configuredMaxHistoryMessages 40}
        {configuredSummarizeHistory false}
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
        if {![string is boolean -strict $configuredSummarizeHistory]} {
            error "Agent summarize_history must be boolean"
        }
        set summarizeHistoryEnabled [expr {$configuredSummarizeHistory ? 1 : 0}]
        set streamCallback $configuredStreamCallback
        set memory [list] ;# Simple list to track conversation history
        set historySummary ""
        set summarizedMessageCount 0

        $log log info "Agent '$name' successfully spawned."
    }

    method run {task} {
        $log log info "Agent execution triggered for task: '$task'"
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
                set response [my runAgentLoop $requestMessages]
                set requestMessages [dict get $response messages]
                set response [dict get $response content]
            }
        } errMsg]} {
            $log log critical "Agent run failed: $errMsg"
            lappend memory \
                $userMessage \
                [dict create role assistant content \
                    "The previous task ended before a final response: $errMsg"]
            return -code error $errMsg
        }

        set newMessages [lrange $requestMessages \
            [llength $requestHistory] end]
        set memory [concat $memory $newMessages]
        $log log info "Thinking cycle completed successfully."
        return $response
    }

    method runAgentLoop {messages} {
        set tools [$pluginRegistry definitions]

        for {set iteration 1} {$iteration <= $maxIterations} {incr iteration} {
            set activeMessages [dict get [my messageWindow $messages] included]
            if {$streamCallback ne "" && "queryMessageStream" in [info object methods $llmClient -all]} {
                set assistantMessage [$llmClient queryMessageStream $systemRole $activeMessages $tools $streamCallback]
                {*}$streamCallback "\n"
            } else {
                set assistantMessage [$llmClient queryMessage $systemRole $activeMessages $tools]
            }

            if {![dict exists $assistantMessage tool_calls] || [llength [dict get $assistantMessage tool_calls]] == 0} {
                lappend messages $assistantMessage
                if {![dict exists $assistantMessage content] || [string trim [dict get $assistantMessage content]] eq ""} {
                    error "Agent returned neither tool calls nor final content"
                }
                return [dict create content [dict get $assistantMessage content] messages $messages]
            }

            lappend messages $assistantMessage
            foreach toolCall [dict get $assistantMessage tool_calls] {
                set callId [dict get $toolCall id]
                set function [dict get $toolCall function]
                set toolName [dict get $function name]
                set arguments [dict get $function arguments]
                $log log info "Executing plugin: $toolName"

                if {[catch {
                    $pluginRegistry invoke $toolName $arguments
                } toolResult]} {
                    set toolResult "Plugin error: $toolResult"
                    $log log warn "Plugin failed: $toolName: $toolResult"
                }
                lappend messages [dict create role tool content $toolResult tool_call_id $callId]
            }
        }

        error "Agent exceeded maximum iterations: $maxIterations"
    }


    method getHistory {} {
        return $memory
    }

    method requestHistory {} {
        return [dict get [my historyWindow] included]
    }

    method historyWindow {} {
        return [my messageWindow $memory]
    }

    method messageWindow {sourceMessages} {
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
        set selectedCount 0
        for {set index [expr {[llength $turns] - 1}]} {$index >= 0} {incr index -1} {
            set turn [lindex $turns $index]
            set turnSize [llength $turn]
            if {$selectedCount > 0 && $selectedCount + $turnSize > $maxHistoryMessages} {
                break
            }
            set selected [concat $turn $selected]
            incr selectedCount $turnSize
            if {$selectedCount >= $maxHistoryMessages} {
                break
            }
        }
        set excludedCount [expr {[llength $sourceMessages] - [llength $selected]}]
        return [dict create included $selected excluded [lrange $sourceMessages 0 [expr {$excludedCount - 1}]]]
    }

    method getExcludedHistory {} {
        return [dict get [my historyWindow] excluded]
    }

    method replaceHistory {messages} {
        set memory $messages
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
