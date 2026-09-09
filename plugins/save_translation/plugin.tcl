namespace eval ::plugins::save_translation {
    variable endpoint https://dev.daidze.org/api/v2/translate/add_new_line
    variable successRedirect https://dev.daidze.org/index.adp?mod=translate&xml=main.xml
    variable successRedirectPath /index.adp?mod=translate&xml=main.xml
    variable requestTimeout 8000
}

proc ::plugins::save_translation::buildPayload {arguments} {
    set fields {}
    foreach name {original pt_pt ch_ch ru_ru fr_fr es_es en_us} {
        set value [string trim [dict get $arguments $name]]
        if {$value eq ""} {
            error "Translation field must not be empty: $name"
        }
        lappend fields $name [::json::write string $value]
    }
    if {![regexp {[\u3400-\u9fff]} [dict get $arguments ch_ch]]} {
        error "Simplified Chinese translation must contain Chinese characters; transliteration is not allowed"
    }
    if {![regexp {[\u0400-\u04ff]} [dict get $arguments ru_ru]]} {
        error "Russian translation must contain Cyrillic characters; transliteration is not allowed"
    }
    return [::json::write object {*}$fields]
}

proc ::plugins::save_translation::responseHeader {metadata wantedName} {
    foreach {name value} $metadata {
        if {[string equal -nocase $name $wantedName]} {
            return $value
        }
    }
    return ""
}

proc ::plugins::save_translation::decodeResponseBody {body} {
    # http::data may already be a decoded Tcl Unicode string. Converting that
    # value from bytes again fails when the response contains native script.
    if {[regexp {[\u0100-\U0010ffff]} $body]} {
        return $body
    }
    if {![catch {encoding convertfrom utf-8 $body} decoded]} {
        return $decoded
    }
    # Some legacy NaviServer responses use a single-byte encoding even when
    # the JSON request is UTF-8. Preserve every response byte for diagnostics.
    return [encoding convertfrom iso8859-1 $body]
}

proc ::plugins::save_translation::execute {workspaceRoot arguments settings} {
    variable endpoint
    variable successRedirect
    variable successRedirectPath
    variable requestTimeout

    package require http
    package require tls
    package require json
    package require json::write

    set payload [buildPayload $arguments]
    set dryRun 0
    if {[dict exists $arguments dry_run]} {
        set configuredDryRun [dict get $arguments dry_run]
        if {![string is boolean -strict $configuredDryRun]} {
            error "dry_run must be boolean"
        }
        set dryRun [expr {$configuredDryRun ? 1 : 0}]
    }
    if {$dryRun} {
        return "Dry run; no request sent.\n$payload"
    }

    ::http::register https 443 [list \
        ::tls::socket \
        -autoservername 1 \
        -ssl2 0 \
        -ssl3 0 \
        -tls1 0 \
        -tls1.1 0 \
        -tls1.2 1 \
        -tls1.3 1]
    set token [::http::geturl $endpoint \
        -query [encoding convertto utf-8 $payload] \
        -type application/json \
        -timeout $requestTimeout]
    try {
        set status [::http::status $token]
        set code [::http::ncode $token]
        set body [decodeResponseBody [::http::data $token]]
        set location [responseHeader [::http::meta $token] Location]

        if {$status eq "ok" && $code >= 200 && $code < 300} {
            return "Translation saved: [dict get $arguments original]"
        }
        if {$status eq "ok" && $code >= 300 && $code < 400
                && $location in [list \
                    $successRedirect $successRedirectPath]} {
            return "Translation saved: [dict get $arguments original]"
        }
        set lowercaseBody [string tolower $body]
        if {$code == 400 \
                && ([string first "duplicate key" $lowercaseBody] >= 0
                || [string first "already exists" $lowercaseBody] >= 0)} {
            error "Translation already exists: [dict get $arguments original]"
        }

        set detail [string trim $body]
        if {$detail eq ""} {
            set detail [::http::error $token]
        }
        error "Translation request failed (HTTP $code): $detail"
    } finally {
        ::http::cleanup $token
    }
}
