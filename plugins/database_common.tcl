package require inifile

namespace eval ::plugins::database_common {}

proc ::plugins::database_common::settings {workspaceRoot pluginSettings} {
    set relative [dict getdef $pluginSettings profile_file .oodz/databases.ini]
    set path [::PluginSupport::resolveWorkspacePath $workspaceRoot $relative]
    if {![file isfile $path]} {
        error "Database profile file does not exist: $relative"
    }
    set ini [::ini::open $path r]
    try {
        if {"database" ni [::ini::sections $ini]} {
            error "Database profile file is missing \[database\]: $relative"
        }
        set result [dict create]
        foreach key [::ini::keys $ini database] {
            dict set result $key [::ini::value $ini database $key]
        }
        set profiles [dict create]
        foreach section [::ini::sections $ini] {
            if {$section eq "database"} {continue}
            if {![regexp {^[A-Za-z0-9_.-]+$} $section]} {
                error "Invalid database profile name: $section"
            }
            set profile [dict create]
            foreach key [::ini::keys $ini $section] {
                dict set profile $key [::ini::value $ini $section $key]
            }
            dict set profiles $section $profile
        }
        dict set result profiles $profiles
        return $result
    } finally {
        ::ini::close $ini
    }
}

proc ::plugins::database_common::profile {configuration requested} {
    set name [string trim $requested]
    if {$name eq ""} {set name [dict getdef $configuration default_profile ""]}
    if {$name eq ""} {error "No database profile was selected and no default_profile is configured"}
    if {![dict exists $configuration profiles $name]} {
        error "Unknown database profile: $name"
    }
    return [list $name [dict get $configuration profiles $name]]
}

proc ::plugins::database_common::open {configuration requested writeAccess} {
    lassign [::plugins::database_common::profile $configuration $requested] name profile
    set packageName [dict getdef $profile package ""]
    if {![regexp {^tdbc::[A-Za-z0-9_:]+$} $packageName]} {
        error "Database profile $name has an invalid TDBC package"
    }
    set allowWrite [dict getdef $profile allow_write false]
    if {![string is boolean -strict $allowWrite]} {
        error "Database profile $name allow_write must be boolean"
    }
    if {$writeAccess && !$allowWrite} {
        error "Database profile does not permit writes: $name"
    }
    if {[catch {package require $packageName} packageError]} {
        error "Cannot load database driver $packageName: $packageError"
    }
    set options [dict getdef $profile options {}]
    if {[catch {llength $options}] || [llength $options] % 2 != 0} {
        error "Database profile $name options must be an option/value Tcl list"
    }
    set passwordEnvironment [string trim [dict getdef $profile password_env ""]]
    if {$passwordEnvironment ne ""} {
        if {![regexp {^[A-Za-z_][A-Za-z0-9_]*$} $passwordEnvironment]} {
            error "Database profile $name has an invalid password_env name"
        }
        if {![info exists ::env($passwordEnvironment)]} {
            error "Database password environment variable is not set: $passwordEnvironment"
        }
        lappend options -password $::env($passwordEnvironment)
    }
    if {!$writeAccess && "-readonly" ni $options} {lappend options -readonly true}
    set constructor ${packageName}::connection
    if {[catch {$constructor new {*}$options} connection optionsDict]} {
        error "Cannot connect using database profile $name: $connection"
    }
    return [list $name $connection]
}

proc ::plugins::database_common::limits {configuration arguments} {
    set maximum [dict getdef $configuration max_rows 100]
    set requested [dict getdef $arguments max_rows $maximum]
    if {![string is entier -strict $maximum] || $maximum < 1 || $maximum > 10000} {
        error "database max_rows must be an integer from 1 to 10000"
    }
    if {![string is entier -strict $requested] || $requested < 1 || $requested > $maximum} {
        error "max_rows must be an integer from 1 to $maximum"
    }
    return $requested
}

proc ::plugins::database_common::bounded {value maximum} {
    if {[string length $value] <= $maximum} {return $value}
    return "[string range $value 0 [expr {$maximum - 1}]]…"
}

proc ::plugins::database_common::formatRows {configuration rows truncated} {
    set maximum [dict getdef $configuration max_value_chars 4096]
    if {![string is entier -strict $maximum] || $maximum < 16} {
        error "database max_value_chars must be an integer of at least 16"
    }
    set result [dict create rows {} returned_rows [llength $rows] truncated $truncated]
    foreach row $rows {
        set boundedRow [dict create]
        dict for {key value} $row {
            dict set boundedRow $key [::plugins::database_common::bounded $value $maximum]
        }
        dict lappend result rows $boundedRow
    }
    return $result
}
