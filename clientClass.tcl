package require http
package require tls
package require json
package require json::write

::oo::class create tHttpTransport {
    variable streamBuffer streamEventData streamBody activeToken activeDone waitDone

    constructor {} {
        set activeToken ""
        set activeDone 0
        set waitDone 0
    }

    destructor {
        my cancel
    }

    method completed {token} {
        set activeDone 1
    }

    method cancel {} {
        if {$activeToken ne ""} {
            catch {::http::reset $activeToken cancelled}
        }
        set waitDone 1
    }

    method post {url payload headers timeout} {
        set activeDone 0
        set activeToken [::http::geturl $url \
            -query [encoding convertto utf-8 $payload] \
            -type "application/json" -headers $headers -timeout $timeout \
            -command [list [self] completed]]
        vwait [namespace which -variable activeDone]
        set token $activeToken
        set activeToken ""
        try {
            return [dict create status [::http::status $token] code [::http::ncode $token] body [encoding convertfrom utf-8 [::http::data $token]] error [::http::error $token]]
        } finally {
            ::http::cleanup $token
        }
    }

    method wait {milliseconds} {
        set waitDone 0
        set timer [after $milliseconds [list set \
            [namespace which -variable waitDone] 1]]
        vwait [namespace which -variable waitDone]
        after cancel $timer
    }

    method postStream {url payload headers timeout eventCallback} {
        set streamBuffer ""
        set streamEventData {}
        set streamBody ""
        set activeDone 0
        set activeToken [::http::geturl $url \
            -query [encoding convertto utf-8 $payload] \
            -type "application/json" -headers $headers -timeout $timeout \
            -handler [list [self] receiveStream $eventCallback] \
            -command [list [self] completed]]
        vwait [namespace which -variable activeDone]
        set token $activeToken
        set activeToken ""
        try {
            set body [encoding convertfrom utf-8 $streamBody]
            if {$body eq "" && [::http::data $token] ne ""} {
                set body [::http::data $token]
            }
            return [dict create status [::http::status $token] code [::http::ncode $token] body $body error [::http::error $token]]
        } finally {
            ::http::cleanup $token
        }
    }

    method receiveStream {eventCallback socket token} {
        set block [read $socket 4096]
        set bytesRead [string length $block]
        append streamBody $block
        append streamBuffer $block

        while {[set newline [string first "\n" $streamBuffer]] >= 0} {
            set line [string range $streamBuffer 0 [expr {$newline - 1}]]
            set streamBuffer [string range $streamBuffer \
                [expr {$newline + 1}] end]
            set line [string trimright $line "\r"]

            if {$line eq ""} {
                if {[llength $streamEventData] > 0} {
                    set event [encoding convertfrom utf-8 \
                        [join $streamEventData "\n"]]
                    set streamEventData {}
                    if {$event ne "\[DONE\]"} {
                        {*}$eventCallback $event
                    }
                }
            } elseif {[string match "data:*" $line]} {
                lappend streamEventData [string trimleft \
                    [string range $line 5 end]]
            }
        }
        return $bytesRead
    }
}

::oo::class create tLLMClient {
    variable log provider apiKey modelUrl modelName timeout
    variable maxRetries retryDelay transport ownsTransport
    variable streamingMessage streamingToolCalls thinkingEnabled
    variable reportedModel cancelRequested diagnostics

    constructor {configObj {transportObj ""}} {
        set log [::tLogger getLogger [self class]]

        set provider [$configObj get "LLM.provider" "deepseek"]
        set apiKey [$configObj get "LLM.api_key"]
        set modelName [$configObj get "LLM.model" "deepseek-v4-flash"]
        set modelUrl  [$configObj get "LLM.url" "https://api.deepseek.com/chat/completions"]
        set timeout   [$configObj get "LLM.timeout" "30000"]
        set maxRetries [$configObj get "LLM.max_retries" "2"]
        set retryDelay [$configObj get "LLM.retry_delay_ms" "250"]
        set configuredThinking [$configObj get "LLM.thinking" "false"]

        if {$provider ni {deepseek ollama}} {
            error "LLM.provider must be one of: deepseek, ollama"
        }
        if {$provider ne "ollama" && [string trim $apiKey] eq ""} {
            error "LLM.api_key is required in conf/conf.ini"
        }
        if {[string trim $modelName] eq ""} {
            error "LLM.model must not be empty"
        }
        if {![regexp {^https?://[^/]+/.+} $modelUrl]} {
            error "LLM.url must be a full HTTP endpoint"
        }
        if {![string is entier -strict $timeout] || $timeout <= 0} {
            error "LLM.timeout must be a positive integer"
        }
        if {![string is entier -strict $maxRetries] || $maxRetries < 0} {
            error "LLM.max_retries must be a non-negative integer"
        }
        if {![string is entier -strict $retryDelay] || $retryDelay <= 0} {
            error "LLM.retry_delay_ms must be a positive integer"
        }
        if {![string is boolean -strict $configuredThinking]} {
            error "LLM.thinking must be boolean"
        }
        set thinkingEnabled [expr {$configuredThinking ? 1 : 0}]
        set reportedModel ""
        set cancelRequested 0
        set diagnostics ""

        if {$transportObj eq ""} {
            set transport [::tHttpTransport new]
            set ownsTransport 1
        } else {
            set transport $transportObj
            set ownsTransport 0
        }

        # Register TLS for HTTPS requests
        ::http::register https 443 [list ::tls::socket -autoservername 1 -ssl2 0 -ssl3 0 -tls1 0 -tls1.1 0 -tls1.2 1 -tls1.3 1]
        $log log info "LLM Client initialized with model: $modelName"
    }

    destructor {
        if {$ownsTransport && [info object isa object $transport]} {
            $transport destroy
        }
    }

    method query {systemPrompt messages} {
        set message [my queryMessage $systemPrompt $messages]
        if {![dict exists $message content]} {
            error "Parsing Error: response has no message content"
        }
        return [dict get $message content]
    }

    method beginRequest {} {
        set cancelRequested 0
    }

    method setDiagnostics {collector} {
        set diagnostics $collector
    }

    method diagnostic {type {details {}}} {
        if {$diagnostics ne ""} {
            $diagnostics record $type $details
        }
    }

    method recordUsage {response} {
        if {$diagnostics eq ""} {return}
        set usage [dict create]
        if {[dict exists $response usage]} {
            set reported [dict get $response usage]
            foreach {source target} {
                prompt_tokens input_tokens
                completion_tokens output_tokens
                total_tokens total_tokens
            } {
                if {[dict exists $reported $source]} {
                    dict set usage $target [dict get $reported $source]
                }
            }
        }
        foreach {source target} {
            prompt_eval_count input_tokens
            eval_count output_tokens
        } {
            if {[dict exists $response $source]} {
                dict set usage $target [dict get $response $source]
            }
        }
        if {![dict exists $usage total_tokens]
                && [dict exists $usage input_tokens]
                && [dict exists $usage output_tokens]} {
            dict set usage total_tokens [expr {
                [dict get $usage input_tokens] + [dict get $usage output_tokens]}]
        }
        if {[dict size $usage] > 0} {$diagnostics record usage $usage}
    }

    method cancel {} {
        set cancelRequested 1
        if {"cancel" in [info object methods $transport -all]} {
            $transport cancel
        }
    }

    method checkCancelled {} {
        if {$cancelRequested} {
            return -code error -errorcode {OODZ CANCELLED} \
                "Request stopped by user"
        }
    }

    method queryMessage {systemPrompt messages {tools {}}} {
        $log log info "Sending HTTP POST request to API..."
        my logRequestShape $messages
        set requestStarted [clock milliseconds]
        my diagnostic llm_request [dict create mode standard \
            message_count [llength $messages] \
            context_chars [string length $messages] tool_count [llength $tools]]

        set payload [my buildPayload $systemPrompt $messages $tools]
        set maxAttempts [expr {$maxRetries + 1}]

        for {set attempt 1} {$attempt <= $maxAttempts} {incr attempt} {
            my checkCancelled
            if {[catch {
                $transport post $modelUrl $payload [my requestHeaders] $timeout
            } response transportOptions]} {
                my checkCancelled
                if {$attempt < $maxAttempts} {
                    $log log warn "Transport failure; retrying ($attempt/$maxAttempts)"
                    my waitBeforeRetry $attempt
                    continue
                }
                my diagnostic llm_error [dict create mode standard \
                    duration_ms [expr {[clock milliseconds] - $requestStarted}]]
                return -options $transportOptions $response
            }

            my checkCancelled
            set status [dict get $response status]
            set code [dict get $response code]
            set body [dict get $response body]

            if {[my isRetryableResponse $status $code]
                    && $attempt < $maxAttempts} {
                $log log warn "Transient API response HTTP $code; retrying ($attempt/$maxAttempts)"
                my waitBeforeRetry $attempt
                continue
            }

            if {$status ne "ok" || $code < 200 || $code >= 300} {
                set detail [my parseErrorResponse $body]
                $log log error "API call failed ($status, HTTP $code)"
            my diagnostic llm_error [dict create mode standard code $code \
                duration_ms [expr {[clock milliseconds] - $requestStarted}]]
            error "[my providerLabel] API Error: HTTP $code: $detail"
            }

            if {![catch {::json::json2dict $body} parsedBody]} {
                my recordUsage $parsedBody
            }
            my diagnostic llm_response [dict create mode standard code $code \
                duration_ms [expr {[clock milliseconds] - $requestStarted}]]
            return [my parseResponseMessage $body]
        }
    }

    method queryMessageStream {
        systemPrompt messages tools contentCallback
    } {
        $log log info "Sending streaming HTTP POST request to API..."
        my logRequestShape $messages
        set requestStarted [clock milliseconds]
        my diagnostic llm_request [dict create mode stream \
            message_count [llength $messages] \
            context_chars [string length $messages] tool_count [llength $tools]]
        set payload [my buildPayload $systemPrompt $messages $tools 1]
        set streamingMessage [dict create role assistant content ""]
        set streamingToolCalls [dict create]

        if {[catch {
            $transport postStream $modelUrl $payload [my requestHeaders] $timeout [list [self] consumeStreamEvent $contentCallback]
        } response]} {
            my checkCancelled
            my diagnostic llm_error [dict create mode stream \
                duration_ms [expr {[clock milliseconds] - $requestStarted}]]
            $log log warn "Streaming transport exception; retrying without streaming"
            set fallbackMessage [my queryMessage $systemPrompt $messages $tools]
            if {[dict exists $fallbackMessage content]
                    && [dict get $fallbackMessage content] ne ""} {
                {*}$contentCallback [dict get $fallbackMessage content]
            }
            return $fallbackMessage
        }
        my checkCancelled
        set status [dict get $response status]
        set code [dict get $response code]
        set body [dict get $response body]

        if {$status ne "ok" || $code < 200 || $code >= 300} {
            if {[string trim [dict get $streamingMessage content]] eq "" && [dict size $streamingToolCalls] == 0} {
                $log log warn "Streaming request failed ($status, HTTP $code); retrying without streaming"
                set fallbackMessage [my queryMessage $systemPrompt $messages $tools]
                if {[dict exists $fallbackMessage content] && [dict get $fallbackMessage content] ne ""} {
                    {*}$contentCallback [dict get $fallbackMessage content]
                }
                return $fallbackMessage
            }
            set detail [my parseErrorResponse $body]
            if {$status ne "ok"} {
                my diagnostic llm_error [dict create mode stream code $code \
                    duration_ms [expr {[clock milliseconds] - $requestStarted}]]
                set transportDetail ""
                if {[dict exists $response error]} {
                    set transportDetail [string trim [dict get $response error]]
                }
                if {$transportDetail ne ""} {
                    error "[my providerLabel] transport error: $status (HTTP $code): $transportDetail"
                }
                error "[my providerLabel] transport error: $status (HTTP $code)"
            }
            $log log error "API streaming call failed (HTTP $code): $detail"
            my diagnostic llm_error [dict create mode stream code $code \
                duration_ms [expr {[clock milliseconds] - $requestStarted}]]
            error "[my providerLabel] API Error: HTTP $code: $detail"
        }

        if {[dict size $streamingToolCalls] > 0} {
            set calls {}
            foreach index [lsort -integer [dict keys $streamingToolCalls]] {
                set call [dict get $streamingToolCalls $index]
                if {[dict get $call type] eq ""} {
                    dict set call type "function"
                }
                lappend calls $call
            }
            dict set streamingMessage tool_calls $calls
        }
        if {[string trim [dict get $streamingMessage content]] eq "" && ![dict exists $streamingMessage tool_calls]} {
            $log log warn "Streaming response was empty; retrying without streaming"
            set fallbackMessage [my queryMessage $systemPrompt $messages $tools]
            if {[dict exists $fallbackMessage content] && [dict get $fallbackMessage content] ne ""} {
                {*}$contentCallback [dict get $fallbackMessage content]
            }
            return $fallbackMessage
        }
        my diagnostic llm_response [dict create mode stream code $code \
            duration_ms [expr {[clock milliseconds] - $requestStarted}]]
        return $streamingMessage
    }

    method consumeStreamEvent {contentCallback data} {
        if {[catch {::json::json2dict $data} event]} {
            return
        }
        my recordReportedModel $event
        my recordUsage $event
        if {![dict exists $event choices]
                || [llength [dict get $event choices]] == 0} {
            return
        }
        set choice [lindex [dict get $event choices] 0]
        if {![dict exists $choice delta]} {
            return
        }
        set delta [dict get $choice delta]

        foreach field {content reasoning_content} {
            if {[dict exists $delta $field] && [dict get $delta $field] ne "null"} {
                set fragment [dict get $delta $field]
                if {![dict exists $streamingMessage $field]} {
                    dict set streamingMessage $field ""
                }
                dict append streamingMessage $field $fragment
                if {$field eq "content" && $fragment ne ""} {
                    {*}$contentCallback $fragment
                }
            }
        }

        if {[dict exists $delta tool_calls]} {
            foreach callDelta [dict get $delta tool_calls] {
                set index [dict get $callDelta index]
                if {![dict exists $streamingToolCalls $index]} {
                    dict set streamingToolCalls $index [dict create id "" type "" function [dict create name "" arguments ""]]
                }
                set call [dict get $streamingToolCalls $index]
                foreach field {id type} {
                    if {[dict exists $callDelta $field]} {
                        dict append call $field [dict get $callDelta $field]
                    }
                }
                if {[dict exists $callDelta function]} {
                    set functionDelta [dict get $callDelta function]
                    set function [dict get $call function]
                    foreach field {name arguments} {
                        if {[dict exists $functionDelta $field]} {
                            dict append function $field [dict get $functionDelta $field]
                        }
                    }
                    dict set call function $function
                }
                dict set streamingToolCalls $index $call
            }
        }
    }

    method isRetryableResponse {status code} {
        expr {$status ne "ok" || $code == 429 || ($code >= 500 && $code < 600)}
    }

    method logRequestShape {messages} {
        set shapes {}
        set index 0
        foreach message $messages {
            set role [dict get $message role]
            set fields [list "#$index" $role]
            if {[dict exists $message content]} {
                lappend fields "content=[string length [dict get $message content]]"
            } else {
                lappend fields "content=missing"
            }
            if {[dict exists $message reasoning_content]} {
                lappend fields "reasoning=[string length [dict get $message reasoning_content]]"
            } elseif {$role eq "assistant"} {
                lappend fields "reasoning=missing"
            }
            if {[dict exists $message tool_calls]} {
                set ids [lmap call [dict get $message tool_calls] {
                    dict get $call id
                }]
                lappend fields "calls=[llength $ids]" "ids=[join $ids ,]"
            }
            if {[dict exists $message tool_call_id]} {
                lappend fields "tool_call_id=[dict get $message tool_call_id]"
            }
            lappend shapes [join $fields " "]
            incr index
        }
        $log log info "Request shape: [join $shapes { | }]"
    }

    method waitBeforeRetry {attempt} {
        set delay [expr {$retryDelay * (1 << ($attempt - 1))}]
        $transport wait $delay
    }

    method requestHeaders {} {
        if {$provider eq "ollama" && [string trim $apiKey] eq ""} {
            return {}
        }
        return [list Authorization "Bearer $apiKey"]
    }

    method providerLabel {} {
        switch -- $provider {
            deepseek {return "DeepSeek"}
            ollama {return "Ollama"}
        }
    }

    method modelInfo {} {
        return [dict create \
            provider $provider \
            configured_model $modelName \
            reported_model [expr {$reportedModel eq "" \
                ? "(not reported yet)" : $reportedModel}]]
    }

    method recordReportedModel {response} {
        if {[dict exists $response model]} {
            set candidate [string trim [dict get $response model]]
            if {$candidate ne "" && $candidate ne "null"} {
                set reportedModel $candidate
            }
        }
    }

    method buildPayload {systemPrompt messages {tools {}} {stream 0}} {
        set encodedMessages [list [my encodeMessage [dict create role system content $systemPrompt]]]

        foreach message $messages {
            lappend encodedMessages [my encodeMessage $message]
        }

        set fields [list model [::json::write string $modelName] messages [::json::write array {*}$encodedMessages]]
        if {$provider eq "deepseek"} {
            lappend fields thinking [::json::write object type [::json::write string [expr {$thinkingEnabled ? "enabled" : "disabled"}]]]
        }

        if {[llength $tools] > 0} {
            set encodedTools {}
            foreach tool $tools {
                foreach key {name description parameters_json} {
                    if {![dict exists $tool $key]} {
                        error "Invalid tool definition: missing $key"
                    }
                }
                lappend encodedTools [::json::write object type [::json::write string "function"] function [::json::write object name [::json::write string [dict get $tool name]] description [::json::write string [dict get $tool description]] parameters [dict get $tool parameters_json]]]
            }
            lappend fields tools [::json::write array {*}$encodedTools]
            # DeepSeek V4 Flash can reject follow-up messages containing
            # multiple parallel tool results even when their IDs match.
            # Sequential calls keep the tool conversation deterministic.
            if {$provider eq "deepseek"} {
                lappend fields parallel_tool_calls false
            }
        }
        if {$stream} {
            lappend fields stream true
        }

        return [::json::write object {*}$fields]
    }

    method encodeMessage {message} {
        if {![dict exists $message role]} {
            error "Message role is required"
        }

        set role [dict get $message role]
        if {$role ni {system user assistant tool}} {
            error "Unsupported message role: $role"
        }
        if {![dict exists $message content]} {
            error "Message content is required"
        }

        set content [dict get $message content]
        set fields [list role [::json::write string $role]]
        # DeepSeek V4 requires non-null assistant content when replaying
        # tool-call messages. Preserve an empty string instead of JSON null.
        lappend fields content [::json::write string $content]

        if {$provider eq "deepseek" && [dict exists $message reasoning_content]} {
            lappend fields reasoning_content [::json::write string [dict get $message reasoning_content]]
        }
        if {[dict exists $message tool_call_id]} {
            if {$role ne "tool"} {
                error "tool_call_id is only valid for tool messages"
            }
            lappend fields tool_call_id [::json::write string [dict get $message tool_call_id]]
        } elseif {$role eq "tool"} {
            error "Tool messages require tool_call_id"
        }
        if {[dict exists $message tool_calls]} {
            if {$role ne "assistant"} {
                error "tool_calls is only valid for assistant messages"
            }
            set encodedCalls {}
            foreach call [dict get $message tool_calls] {
                foreach path {
                    id type {function name} {function arguments}
                } {
                    if {![dict exists $call {*}$path]} {
                        error "Invalid tool call: missing [join $path .]"
                    }
                }
                set function [dict get $call function]
                lappend encodedCalls [::json::write object id [::json::write string [dict get $call id]] type [::json::write string [dict get $call type]] function [::json::write object name [::json::write string [dict get $function name]] arguments [::json::write string [dict get $function arguments]]]]
            }
            lappend fields tool_calls [::json::write array {*}$encodedCalls]
        }

        return [::json::write object {*}$fields]
    }

    method parseResponse {body} {
        set message [my parseResponseMessage $body]
        if {![dict exists $message content]} {
            error "Parsing Error: response has no message content"
        }
        return [dict get $message content]
    }

    method parseResponseMessage {body} {
        if {[catch {::json::json2dict $body} response]} {
            return -code error "Parsing Error: invalid JSON response"
        }
        my recordReportedModel $response

        if {![dict exists $response choices] || [llength [dict get $response choices]] == 0 || ![dict exists [lindex [dict get $response choices] 0] message]} {
            return -code error "Parsing Error: response has no assistant message"
        }

        set rawMessage [dict get [lindex [dict get $response choices] 0] message]
        if {![dict exists $rawMessage role] || [dict get $rawMessage role] ne "assistant"} {
            return -code error "Parsing Error: invalid assistant message"
        }

        set message [dict create role assistant]
        if {[dict exists $rawMessage content]} {
            set content [dict get $rawMessage content]
            if {$content eq "null"} {
                set content ""
            }
            dict set message content $content
        }
        foreach field {reasoning_content tool_calls} {
            if {[dict exists $rawMessage $field]} {
                dict set message $field [dict get $rawMessage $field]
            }
        }
        if {![dict exists $message content] && ![dict exists $message tool_calls]} {
            return -code error "Parsing Error: response has no message content"
        }
        return $message
    }

    method parseErrorResponse {body} {
        if {![catch {::json::json2dict $body} response] && [dict exists $response error message]} {
            return [dict get $response error message]
        }
        return "request failed"
    }
}
