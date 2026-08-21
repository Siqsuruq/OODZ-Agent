package require http
package require json
package require tls

namespace eval ::plugins::http_common {}

proc ::plugins::http_common::positiveInteger {
    toolName settings key defaultValue
} {
    set value $defaultValue
    if {[dict exists $settings $key]} {
        set value [dict get $settings $key]
    }
    if {![string is entier -strict $value] || $value <= 0} {
        error "$toolName setting must be a positive integer: $key"
    }
    return $value
}

proc ::plugins::http_common::validateJson {toolName jsonBody} {
    if {![regexp {^\s*\{} $jsonBody]} {
        error "$toolName json must be a JSON object"
    }
    if {[catch {::json::json2dict $jsonBody}]} {
        error "$toolName json is not valid JSON"
    }
    return $jsonBody
}

proc ::plugins::http_common::buildUrl {toolName arguments settings} {
    foreach key {base_url allowed_path_prefixes} {
        if {![dict exists $settings $key]
                || [string trim [dict get $settings $key]] eq ""} {
            error "$toolName setting is required: $key"
        }
    }
    set baseUrl [string trimright \
        [string trim [dict get $settings base_url]] "/"]
    if {![regexp {^https?://[^/?#]+(?::[0-9]+)?(?:/[^?#]*)?$} $baseUrl]} {
        error "$toolName base_url must be a fixed HTTP origin or base path"
    }

    set path [dict get $arguments path]
    if {![string match "/*" $path]
            || [string first "?" $path] >= 0
            || [string first "#" $path] >= 0
            || [regexp {(^|/)\.\.?(/|$)} $path]
            || [regexp {^[[:space:]]*//} $path]} {
        error "$toolName path must be an absolute-path reference without query, fragment, or traversal"
    }
    set allowed 0
    foreach prefix [split [dict get $settings allowed_path_prefixes] ,] {
        set prefix [string trim $prefix]
        if {$prefix eq ""} {
            continue
        }
        if {![string match "/*" $prefix]
                || [string first "?" $prefix] >= 0
                || [string first "#" $prefix] >= 0} {
            error "$toolName allowed path prefix is invalid: $prefix"
        }
        set normalizedPrefix [string trimright $prefix "/"]
        if {$path eq $normalizedPrefix
                || [string first "$normalizedPrefix/" $path] == 0} {
            set allowed 1
            break
        }
    }
    if {!$allowed} {
        error "$toolName path is outside allowed prefixes"
    }

    set url "$baseUrl$path"
    if {[dict exists $arguments query]} {
        set queryParts {}
        dict for {key value} [dict get $arguments query] {
            if {[catch {string length $key}]
                    || [catch {string length $value}]} {
                error "$toolName query keys and values must be strings"
            }
            lappend queryParts $key $value
        }
        if {[llength $queryParts] > 0} {
            append url ? [::http::formatQuery {*}$queryParts]
        }
    }
    return $url
}

proc ::plugins::http_common::tlsOptions {toolName settings} {
    set verify true
    if {[dict exists $settings tls_verify]
            && [string trim [dict get $settings tls_verify]] ne ""} {
        set verify [dict get $settings tls_verify]
    }
    if {![string is boolean -strict $verify]} {
        error "$toolName setting must be boolean: tls_verify"
    }
    set options [list \
        ::tls::socket -autoservername 1 \
        -ssl2 0 -ssl3 0 -tls1 0 -tls1.1 0 -tls1.2 1 -tls1.3 1 \
        -require [expr {$verify ? 1 : 0}]]
    if {$verify && [dict exists $settings tls_ca_file]
            && [string trim [dict get $settings tls_ca_file]] ne ""} {
        set caFile [file normalize [dict get $settings tls_ca_file]]
        if {![file isfile $caFile] || ![file readable $caFile]} {
            error "$toolName TLS CA file is not readable"
        }
        lappend options -cafile $caFile
    }
    return $options
}

proc ::plugins::http_common::customHeaders {toolName settings} {
    set headers [list Accept application/json]
    set seen [dict create accept 1]
    set managed {
        accept connection content-length content-type host
        proxy-connection transfer-encoding
    }
    dict for {key value} $settings {
        if {![string match -nocase "header.*" $key]} {
            continue
        }
        set name [string range $key 7 end]
        set normalizedName [string tolower $name]
        if {$name eq ""
                || ![regexp {^[A-Za-z0-9!#$%&'*+.^_`|~-]+$} $name]} {
            error "$toolName custom header name is invalid: $name"
        }
        if {$normalizedName in $managed} {
            error "$toolName custom header is managed internally: $name"
        }
        if {[dict exists $seen $normalizedName]} {
            error "$toolName custom header is duplicated: $name"
        }
        if {[string first "\r" $value] >= 0
                || [string first "\n" $value] >= 0} {
            error "$toolName custom header value contains a newline: $name"
        }
        dict set seen $normalizedName 1
        lappend headers $name $value
    }
    return $headers
}

proc ::plugins::http_common::request {
    toolName method arguments settings jsonMode
} {
    set timeout [positiveInteger $toolName $settings timeout_ms 10000]
    set maxResponse [positiveInteger \
        $toolName $settings max_response_chars 65536]
    set url [buildUrl $toolName $arguments $settings]
    set requestOptions [list \
        -method $method \
        -headers [customHeaders $toolName $settings] \
        -timeout $timeout]

    set hasJson [dict exists $arguments json]
    if {$jsonMode eq "required" && !$hasJson} {
        error "$toolName json is required"
    }
    if {$jsonMode eq "none" && $hasJson} {
        error "$toolName does not accept json"
    }
    if {$hasJson} {
        set jsonBody [validateJson $toolName [dict get $arguments json]]
        lappend requestOptions \
            -type "application/json; charset=utf-8" \
            -query [encoding convertto utf-8 $jsonBody]
    }

    if {[string match "https://*" $url]} {
        ::http::register https 443 [tlsOptions $toolName $settings]
    }
    if {[catch {::http::geturl $url {*}$requestOptions} token]} {
        error "$toolName transport failed: $token"
    }
    try {
        set status [::http::status $token]
        set code [::http::ncode $token]
        set bytes [::http::data $token]
        if {[string length $bytes] > $maxResponse} {
            error "$toolName response exceeds configured limit"
        }
        if {[catch {encoding convertfrom utf-8 $bytes} body]} {
            error "$toolName response is not valid UTF-8"
        }
        set transportError [string trim [::http::error $token]]
        if {$status ne "ok"} {
            if {$transportError eq ""} {
                set transportError "request failed"
            }
            error "$toolName transport failed: $transportError"
        }
        return "HTTP $code\n$body"
    } finally {
        ::http::cleanup $token
    }
}
