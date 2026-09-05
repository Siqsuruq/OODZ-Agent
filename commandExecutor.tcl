::oo::class create tCommandExecutor {
    variable workspaceRoot runner mode executablePolicies
    variable defaultTimeout maxTimeout maxOutput

    constructor {
        configuredWorkspaceRoot configuredRunner configuredMode
        configuredPolicies configuredDefaultTimeout configuredMaxTimeout
        configuredMaxOutput
    } {
        set workspaceRoot [file normalize $configuredWorkspaceRoot]
        if {![info object isa typeof $configuredRunner tProcessRunner]} {
            error "Command execution requires a process runner"
        }
        set runner $configuredRunner
        set mode [string tolower [string trim $configuredMode]]
        if {$mode ni {allowlist unrestricted}} {
            error "CommandExecution.mode must be one of: allowlist, unrestricted"
        }
        if {[catch {dict size $configuredPolicies}]} {
            error "Command execution policies must be a dictionary"
        }
        set executablePolicies $configuredPolicies
        foreach {value label} [list \
            $configuredDefaultTimeout CommandExecution.timeout_ms \
            $configuredMaxTimeout CommandExecution.max_timeout_ms \
            $configuredMaxOutput CommandExecution.max_output_chars] {
            if {![string is entier -strict $value] || $value <= 0} {
                error "$label must be a positive integer"
            }
        }
        if {$configuredDefaultTimeout > $configuredMaxTimeout} {
            error "CommandExecution.timeout_ms must not exceed max_timeout_ms"
        }
        set defaultTimeout $configuredDefaultTimeout
        set maxTimeout $configuredMaxTimeout
        set maxOutput $configuredMaxOutput
    }

    method cancel {} {
        $runner cancel
        return
    }

    method rejectControlArguments {arguments} {
        foreach argument $arguments {
            if {$argument eq "&"
                    || [regexp {^([0-9]*[<>]|\|)} $argument]} {
                error "Command argument is reserved by Tcl process execution: $argument"
            }
        }
    }

    method matchesPrefix {arguments configuredPrefixes} {
        if {[string trim $configuredPrefixes] eq "*"} {
            return 1
        }
        if {[catch {llength $configuredPrefixes}]} {
            error "allowed_prefixes must be a valid Tcl list"
        }
        foreach configuredPrefix $configuredPrefixes {
            if {[catch {llength $configuredPrefix}]} {
                error "Each allowed command prefix must be a valid Tcl list"
            }
            set prefixLength [llength $configuredPrefix]
            if {$prefixLength == 0} {
                continue
            }
            if {[lrange $arguments 0 [expr {$prefixLength - 1}]] \
                    eq $configuredPrefix} {
                return 1
            }
        }
        return 0
    }

    method prepare {executable arguments workingDirectory requestedTimeout} {
        set executable [string trim $executable]
        if {$executable eq ""} {
            error "Command executable must not be empty"
        }
        if {[catch {llength $arguments}]} {
            error "Command arguments must be a valid Tcl list"
        }
        my rejectControlArguments $arguments

        set configuredExecutable $executable
        set allowedPrefixes "*"
        if {$mode eq "allowlist"} {
            if {![dict exists $executablePolicies $executable]} {
                error "Command executable is not allowed: $executable"
            }
            set policy [dict get $executablePolicies $executable]
            set configuredExecutable [dict get $policy executable]
            set allowedPrefixes [dict get $policy allowed_prefixes]
            if {![my matchesPrefix $arguments $allowedPrefixes]} {
                error "Command arguments do not match an allowed prefix for: $executable"
            }
        }
        set resolved [auto_execok $configuredExecutable]
        if {$resolved eq ""} {
            error "Command executable was not found: $configuredExecutable"
        }
        set resolved [file normalize [lindex $resolved 0]]

        set workingDirectory [string trim $workingDirectory]
        if {$workingDirectory eq ""} {
            set workingDirectory "."
        }
        set resolvedDirectory [::PluginSupport::resolveWorkspacePath \
            $workspaceRoot $workingDirectory]
        if {![file isdirectory $resolvedDirectory]} {
            error "Command working directory does not exist: $workingDirectory"
        }

        set timeout $defaultTimeout
        if {$requestedTimeout ne ""} {
            if {![string is entier -strict $requestedTimeout]
                    || $requestedTimeout <= 0} {
                error "Command timeout_ms must be a positive integer"
            }
            if {$requestedTimeout > $maxTimeout} {
                error "Command timeout_ms exceeds configured limit: $maxTimeout"
            }
            set timeout $requestedTimeout
        }
        return [dict create \
            logical_executable $executable \
            resolved_executable $resolved \
            arguments $arguments \
            working_directory $workingDirectory \
            resolved_working_directory $resolvedDirectory \
            timeout_ms $timeout \
            max_output_chars $maxOutput]
    }

    method execute {prepared} {
        $runner runExternalCommand \
            [dict get $prepared resolved_executable] \
            [dict get $prepared arguments] \
            [dict get $prepared resolved_working_directory] \
            [dict get $prepared timeout_ms] \
            [dict get $prepared max_output_chars]
    }

    method mode {} {return $mode}
}
