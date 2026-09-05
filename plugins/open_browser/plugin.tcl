namespace eval ::plugins::open_browser {}

proc ::plugins::open_browser::validateUrl {value} {
    if {[string length $value] > 2048} {
        error "open_browser URL exceeds 2048 characters"
    }
    if {[regexp {[\x00-\x20\x7f]} $value]} {
        error "open_browser URL must not contain whitespace or control characters"
    }
    if {![regexp -nocase {^https?://([^/?#]+)} $value -> authority]} {
        error "open_browser accepts only complete HTTP or HTTPS URLs"
    }
    if {[string first @ $authority] >= 0} {
        error "open_browser URL must not contain credentials"
    }
    return $value
}

proc ::plugins::open_browser::execute {
    workspaceRoot arguments settings
} {
    if {[dict exists $arguments url]} {
        set url [::plugins::open_browser::validateUrl [dict get $arguments url]]
    } else {
        set url [dict get $settings default_url]
    }
    set platform [::PluginSupport::currentPlatform]
    switch -- $platform {
        linux {
            set executable [dict get $settings linux_executable]
            set commandArguments [list $url]
        }
        windows {
            set executable [dict get $settings windows_executable]
            set commandArguments [list url.dll,FileProtocolHandler $url]
        }
        default {
            error "open_browser is not supported on platform: $platform"
        }
    }
    ::PluginSupport::formatProcessResult [::PluginSupport::runConfiguredCommand $executable $commandArguments]
}
