namespace eval ::plugins::large_test {}

proc ::plugins::large_test::execute {workspaceRoot arguments settings} {
    return [string repeat x 100]
}
