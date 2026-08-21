namespace eval ::plugins::file_info {}

proc ::plugins::file_info::execute {workspaceRoot arguments settings} {
    set relativePath [string trim [dict get $arguments path]]
    if {$relativePath eq ""} {
        error "Path must not be empty"
    }

    set path [::PluginSupport::resolveWorkspacePath \
        $workspaceRoot $relativePath]
    if {[catch {file lstat $path metadata}]} {
        error "Path does not exist: $relativePath"
    }

    set modified [clock format $metadata(mtime) \
        -format {%Y-%m-%dT%H:%M:%SZ} -gmt true]
    set permissions "unavailable"
    if {![catch {file attributes $path -permissions} value]} {
        set permissions $value
    }

    return [join [list \
        "Path: $relativePath" \
        "Type: $metadata(type)" \
        "Size: $metadata(size) bytes" \
        "Modified: $modified" \
        "Permissions: $permissions" \
        "Readable: [file readable $path]" \
        "Writable: [file writable $path]"] "\n"]
}
