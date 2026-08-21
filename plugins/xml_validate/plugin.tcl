namespace eval ::plugins::xml_validate {}

proc ::plugins::xml_validate::rejectExternalEntity {args} {
    error "External XML entities are not allowed"
}

proc ::plugins::xml_validate::execute {workspaceRoot arguments settings} {
    set relativePath [string trim [dict get $arguments path]]
    if {$relativePath eq ""} {
        error "Path must not be empty"
    }

    set path [::PluginSupport::resolveWorkspacePath \
        $workspaceRoot $relativePath]
    if {![file isfile $path]} {
        error "XML file does not exist: $relativePath"
    }

    if {[catch {package require tdom} packageError]} {
        error "xml_validate requires the tdom package: $packageError"
    }

    set channel [open $path r]
    try {
        fconfigure $channel -encoding utf-8
        set xml [read $channel]
    } finally {
        close $channel
    }

    set document ""
    try {
        if {[catch {
            set document [dom parse \
                -externalentitycommand \
                ::plugins::xml_validate::rejectExternalEntity $xml]
        } parseError]} {
            error "Invalid XML in $relativePath: $parseError"
        }
        set root [[$document documentElement] nodeName]
        return "Valid XML: $relativePath\nRoot element: $root"
    } finally {
        if {$document ne ""} {
            $document delete
        }
    }
}
