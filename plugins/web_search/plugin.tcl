package require http
package require json
package require tls

namespace eval ::plugins::web_search {}

proc ::plugins::web_search::positiveInteger {
    value label minimum maximum
} {
    if {![string is entier -strict $value]
            || $value < $minimum || $value > $maximum} {
        error "$label must be an integer from $minimum to $maximum"
    }
    return $value
}

proc ::plugins::web_search::buildUrls {arguments settings} {
    set query [string trim [dict get $arguments query]]
    if {$query eq ""} {
        error "web_search query must not be empty"
    }
    if {[string length $query] > 500} {
        error "web_search query exceeds 500 characters"
    }
    if {![dict exists $settings base_urls]
            || [string trim [dict get $settings base_urls]] eq ""} {
        error "web_search requires SearXNG base_urls in plugin settings"
    }
    set safeSearch [positiveInteger \
        [dict get $settings safe_search] \
        "web_search safe_search setting" 0 2]
    set language [string trim [dict get $settings language]]
    if {$language eq "" || ![regexp {^[A-Za-z0-9-]+$} $language]} {
        error "web_search language setting is invalid"
    }
    set queryString [::http::formatQuery \
        q $query format json safesearch $safeSearch language $language]
    set urls {}
    foreach configured [split [dict get $settings base_urls] ,] {
        set baseUrl [string trimright [string trim $configured] /]
        if {$baseUrl eq ""} {
            continue
        }
        if {![regexp {^https?://[^/@?#]+(?::[0-9]+)?(?:/[^?#]*)?$} \
                $baseUrl]} {
            error "web_search base_urls contains an invalid HTTP origin or base path"
        }
        set url "$baseUrl/search?$queryString"
        if {$url ni $urls} {
            lappend urls $url
        }
    }
    if {[llength $urls] == 0} {
        error "web_search requires SearXNG base_urls in plugin settings"
    }
    return $urls
}

proc ::plugins::web_search::compact {value maximum} {
    regsub -all {\s+} [string trim $value] { } value
    if {[string length $value] <= $maximum} {
        return $value
    }
    return "[string range $value 0 [expr {$maximum - 2}]]…"
}

proc ::plugins::web_search::formatResults {query body limit} {
    if {[catch {::json::json2dict $body} response]
            || ![dict exists $response results]} {
        error "web_search response is not valid SearXNG JSON"
    }
    set lines {}
    foreach result [dict get $response results] {
        if {[llength $lines] >= $limit} {
            break
        }
        if {![dict exists $result title] || ![dict exists $result url]} {
            continue
        }
        set url [string trim [dict get $result url]]
        if {![regexp -nocase {^https?://[^[:space:]]+$} $url]} {
            continue
        }
        set title [compact [dict get $result title] 200]
        if {$title eq ""} {
            set title "(untitled result)"
        }
        set snippet ""
        if {[dict exists $result content]} {
            set snippet [compact [dict get $result content] 500]
        }
        set item "[expr {[llength $lines] + 1}]. $title\n$url"
        if {$snippet ne ""} {
            append item "\n$snippet"
        }
        lappend lines $item
    }
    if {[llength $lines] == 0} {
        return "No web results found for: $query"
    }
    return "Web results for: $query\n\n[join $lines \n\n]"
}

proc ::plugins::web_search::request {url settings} {
    set timeout [positiveInteger [dict get $settings timeout_ms] "web_search timeout setting" 1 120000]
    set maximum [positiveInteger [dict get $settings max_response_chars] "web_search response limit setting" 1 4194304]
    if {[string match "https://*" $url]} {
        set verify [dict get $settings tls_verify]
        if {![string is boolean -strict $verify]} {
            error "web_search tls_verify setting must be boolean"
        }
        ::http::register https 443 [list ::tls::socket -autoservername 1 -ssl2 0 -ssl3 0 -tls1 0 -tls1.1 0 -tls1.2 1 -tls1.3 1 -require [expr {$verify ? 1 : 0}]]
    }
    if {[catch {::http::geturl $url -headers [list Accept application/json] -timeout $timeout} token]} {
        error "web_search transport failed: $token"
    }
    try {
        set status [::http::status $token]
        set code [::http::ncode $token]
        set bytes [::http::data $token]
        if {[string length $bytes] > $maximum} {
            error "web_search response exceeds configured limit"
        }
        if {$status ne "ok" || $code < 200 || $code >= 300} {
            error "web_search request failed: HTTP $code"
        }
        if {[catch {encoding convertfrom utf-8 $bytes} body]} {
            error "web_search response is not valid UTF-8"
        }
        return $body
    } finally {
        ::http::cleanup $token
    }
}

proc ::plugins::web_search::searchWith {
    arguments settings requestCommand
} {
    set limit 5
    if {[dict exists $arguments limit]} {
        set limit [dict get $arguments limit]
    }
    set limit [positiveInteger $limit "web_search limit" 1 10]
    set query [string trim [dict get $arguments query]]
    set failures {}
    foreach url [buildUrls $arguments $settings] {
        if {[catch {
            set body [{*}$requestCommand $url $settings]
            set result [formatResults $query $body $limit]
        } message]} {
            lappend failures $message
            continue
        }
        set origin [lindex [regexp -inline {^https?://[^/]+} $url] 0]
        return "$result\n\nSearch backend: $origin"
    }
    error "All configured SearXNG instances failed: [join $failures { | }]"
}

proc ::plugins::web_search::execute {
    workspaceRoot arguments settings
} {
    searchWith $arguments $settings ::plugins::web_search::request
}
