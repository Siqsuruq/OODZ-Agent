namespace eval ::plugins::settings_test {}

proc ::plugins::settings_test::execute {
    workspaceRoot arguments settings
} {
    return [dict get $settings base_url]
}
