package require json
package require json::write

::oo::class create tConversationStore {
    variable historyPath

    constructor {path} {
        if {[string trim $path] eq ""} {
            error "Conversation history path must not be empty"
        }
        set historyPath [file normalize $path]
    }

    method encodeToolCall {call} {
        foreach field {id type function} {
            if {![dict exists $call $field]} {
                error "Conversation tool call is missing '$field'"
            }
        }
        set function [dict get $call function]
        foreach field {name arguments} {
            if {![dict exists $function $field]} {
                error "Conversation tool function is missing '$field'"
            }
        }

        return [::json::write object id [::json::write string [dict get $call id]] type [::json::write string [dict get $call type]] function [::json::write object name [::json::write string [dict get $function name]] arguments [::json::write string [dict get $function arguments]]]]
    }

    method encodeMessage {message} {
        if {![dict exists $message role]} {
            error "Conversation message is missing 'role'"
        }
        set role [dict get $message role]
        if {$role ni {user assistant tool}} {
            error "Unsupported conversation role: $role"
        }

        set fields [list role [::json::write string $role]]
        foreach field {content reasoning_content tool_call_id} {
            if {[dict exists $message $field]} {
                lappend fields $field [::json::write string [dict get $message $field]]
            }
        }
        if {[dict exists $message tool_calls]} {
            set calls {}
            foreach call [dict get $message tool_calls] {
                lappend calls [my encodeToolCall $call]
            }
            lappend fields tool_calls [::json::write array {*}$calls]
        }
        return [::json::write object {*}$fields]
    }

    method validateMessage {message} {
        if {![dict exists $message role]} {
            error "Stored conversation message is missing 'role'"
        }
        set role [dict get $message role]
        if {$role ni {user assistant tool}} {
            error "Stored conversation has unsupported role: $role"
        }
        if {$role in {user tool} && ![dict exists $message content]} {
            error "Stored $role message is missing 'content'"
        }
        if {$role eq "tool" && ![dict exists $message tool_call_id]} {
            error "Stored tool message is missing 'tool_call_id'"
        }
        return $message
    }

    method save {messages {summary ""} {summarizedMessages 0}} {
        if {![string is entier -strict $summarizedMessages] || $summarizedMessages < 0 || $summarizedMessages > [llength $messages]} {
            error "Invalid summarized message count"
        }
        set encodedMessages {}
        foreach message $messages {
            lappend encodedMessages [my encodeMessage $message]
        }
        set document [::json::write object version 1 summary [::json::write string $summary] summarized_messages $summarizedMessages messages [::json::write array {*}$encodedMessages]]

        set parent [file dirname $historyPath]
        file mkdir $parent
        set channel [file tempfile temporaryPath [file join $parent .oodz-history-XXXXXX]]
        try {
            fconfigure $channel -encoding utf-8 -translation lf
            puts -nonewline $channel $document
            close $channel
            set channel ""
            catch {file attributes $temporaryPath -permissions 0600}
            file rename -force $temporaryPath $historyPath
        } finally {
            if {$channel ne ""} {
                close $channel
            }
            if {[file exists $temporaryPath]} {
                file delete $temporaryPath
            }
        }
        return
    }

    method load {} {
        return [dict get [my loadState] messages]
    }

    method loadState {} {
        if {![file exists $historyPath]} {
            return [dict create messages {} summary "" summarized_messages 0]
        }
        set channel [open $historyPath r]
        try {
            fconfigure $channel -encoding utf-8
            set document [::json::json2dict [read $channel]]
        } finally {
            close $channel
        }
        if {![dict exists $document version] || [dict get $document version] != 1} {
            error "Unsupported conversation history version"
        }
        if {![dict exists $document messages]} {
            error "Conversation history is missing 'messages'"
        }

        set messages {}
        foreach message [dict get $document messages] {
            lappend messages [my validateMessage $message]
        }
        set summary [expr {[dict exists $document summary] ? [dict get $document summary] : ""}]
        set summarizedMessages [expr {[dict exists $document summarized_messages] ? [dict get $document summarized_messages] : 0}]
        if {![string is entier -strict $summarizedMessages] || $summarizedMessages < 0 || $summarizedMessages > [llength $messages]} {
            error "Invalid summarized message count"
        }
        return [dict create messages $messages summary $summary summarized_messages $summarizedMessages]
    }

    method saveState {state} {
        foreach field {messages summary summarized_messages} {
            if {![dict exists $state $field]} {
                error "Conversation state is missing '$field'"
            }
        }
        my save [dict get $state messages] [dict get $state summary] [dict get $state summarized_messages]
    }

    method clear {} {
        if {[file exists $historyPath]} {
            file delete $historyPath
        }
        return
    }
}
