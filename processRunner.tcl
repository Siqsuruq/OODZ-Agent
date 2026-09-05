::oo::class create tProcessRunner {
    variable workspaceRoot tclExecutable
    variable timeoutMs maxOutput activeMaxOutput executor channel output done overflow
    variable processIds watchdog terminationReason
    variable projectTestsEnabled projectTestsExecutable
    variable projectTestsArguments projectTestsTimeout
    variable executableAliases

    constructor {
        configuredWorkspaceRoot configuredTclExecutable
        configuredTimeoutMs configuredMaxOutput
        {configuredExecutor ""} {configuredExecutableAliases {}}
    } {
        set workspaceRoot [file normalize $configuredWorkspaceRoot]
        if {![file isdirectory $workspaceRoot]} {
            error "Runner workspace root is not a directory"
        }
        set tclExecutable [my resolveExecutable \
            $configuredTclExecutable "Runner.tclsh"]
        if {![string is entier -strict $configuredTimeoutMs]
                || $configuredTimeoutMs <= 0} {
            error "Runner timeout must be a positive integer"
        }
        if {![string is entier -strict $configuredMaxOutput]
                || $configuredMaxOutput <= 0} {
            error "Runner output limit must be a positive integer"
        }
        set timeoutMs $configuredTimeoutMs
        set maxOutput $configuredMaxOutput
        set activeMaxOutput $maxOutput
        set executor $configuredExecutor
        if {[catch {dict size $configuredExecutableAliases}]} {
            error "Executable aliases must be a dictionary"
        }
        set executableAliases $configuredExecutableAliases
        set channel ""
        set projectTestsEnabled 0
        set projectTestsExecutable ""
        set projectTestsArguments {}
        set projectTestsTimeout $timeoutMs
    }

    destructor {
        if {$channel ne ""} {
            catch {fileevent $channel readable {}}
            catch {close $channel}
        }
    }

    method resolveExecutable {configuredValue label} {
        set configuredValue [string trim $configuredValue]
        if {$configuredValue eq ""} {
            error "$label must not be empty"
        }
        set resolved [auto_execok $configuredValue]
        if {$resolved eq ""} {
            error "$label executable was not found: $configuredValue"
        }
        return [file normalize [lindex $resolved 0]]
    }

    method runTclFile {relativePath} {
        set command [my buildTclCommand $relativePath]
        if {$executor ne ""} {
            return [{*}$executor $command $timeoutMs $maxOutput]
        }
        return [my execute $command]
    }

    method mode {} {
        return direct
    }

    method configureProjectTests {
        configuredExecutable configuredArguments configuredTimeout
    } {
        set projectTestsExecutable [my resolveExecutable \
            $configuredExecutable "Runner.project_tests_executable"]
        if {[catch {llength $configuredArguments}]} {
            error "Runner.project_tests_arguments must be a valid Tcl list"
        }
        if {![string is entier -strict $configuredTimeout]
                || $configuredTimeout <= 0} {
            error "Runner.project_tests_timeout_ms must be a positive integer"
        }
        set projectTestsArguments $configuredArguments
        set projectTestsTimeout $configuredTimeout
        set projectTestsEnabled 1
    }

    method hasProjectTests {} {
        return $projectTestsEnabled
    }

    method runProjectTests {} {
        if {!$projectTestsEnabled} {
            error "Project test profile is not configured"
        }
        set command [list \
            $projectTestsExecutable {*}$projectTestsArguments]
        if {$executor ne ""} {
            return [{*}$executor $command $projectTestsTimeout $maxOutput]
        }
        return [my execute $command $projectTestsTimeout]
    }

    method runConfiguredCommand {configuredExecutable arguments} {
        if {[catch {llength $arguments}]} {
            error "Configured command arguments must be a valid Tcl list"
        }
        set executableName [string trim $configuredExecutable]
        if {[dict exists $executableAliases $executableName]} {
            set configuredExecutable [dict get \
                $executableAliases $executableName]
        }
        set executable [my resolveExecutable \
            $configuredExecutable "Plugin executable"]
        set command [list $executable {*}$arguments]
        if {$executor ne ""} {
            return [{*}$executor $command $timeoutMs $maxOutput]
        }
        return [my execute $command]
    }

    method runExternalCommand {
        executable arguments workingDirectory executionTimeout outputLimit
    } {
        if {[catch {llength $arguments}]} {
            error "External command arguments must be a valid Tcl list"
        }
        set resolvedExecutable [my resolveExecutable \
            $executable "Command executable"]
        set workingDirectory [file normalize $workingDirectory]
        if {![::PluginSupport::isWithin $workingDirectory $workspaceRoot]} {
            error "Command working directory escapes the workspace"
        }
        if {![file isdirectory $workingDirectory]} {
            error "Command working directory is not a directory"
        }
        if {![string is entier -strict $executionTimeout]
                || $executionTimeout <= 0} {
            error "Command timeout must be a positive integer"
        }
        if {![string is entier -strict $outputLimit] || $outputLimit <= 0} {
            error "Command output limit must be a positive integer"
        }
        set command [list $resolvedExecutable {*}$arguments]
        if {$executor ne ""} {
            return [{*}$executor $command $executionTimeout $outputLimit]
        }
        return [my execute $command $executionTimeout \
            $workingDirectory $outputLimit]
    }

    method buildTclCommand {relativePath} {
        if {[file pathtype $relativePath] ne "relative"} {
            error "Runner paths must be relative to the workspace"
        }
        set path [::PluginSupport::resolveWorkspacePath \
            $workspaceRoot $relativePath]
        if {![file isfile $path]} {
            error "Tcl runner file does not exist: $relativePath"
        }
        if {[string tolower [file extension $path]] ne ".tcl"} {
            error "Tcl runner accepts only .tcl files"
        }

        return [list $tclExecutable $path]
    }

    method execute {
        command {executionTimeout ""} {workingDirectory ""} {outputLimit ""}
    } {
        if {$executionTimeout eq ""} {
            set executionTimeout $timeoutMs
        }
        if {$workingDirectory eq ""} {
            set workingDirectory $workspaceRoot
        }
        if {$outputLimit eq ""} {
            set outputLimit $maxOutput
        }
        set activeMaxOutput $outputLimit
        set output ""
        set done 0
        set overflow 0
        set terminationReason ""
        set startedAt [clock milliseconds]
        set pipeline [concat [list |] $command [list 2>@1]]
        set previousDirectory [pwd]
        try {
            cd $workingDirectory
            set channel [open $pipeline r]
        } finally {
            cd $previousDirectory
        }
        fconfigure $channel \
            -blocking 0 -translation binary -encoding iso8859-1
        set processIds [pid $channel]
        fileevent $channel readable [list [self] collectOutput]
        set watchdog [after $executionTimeout \
            [list [self] terminate timeout]]
        vwait [namespace which -variable done]
        after cancel $watchdog

        catch {fconfigure $channel -blocking 1}
        set closeCode [catch {close $channel} closeMessage closeOptions]
        set channel ""
        set durationMs [expr {[clock milliseconds] - $startedAt}]
        set text [my decodeOutput $output]
        set exitCode 0
        if {$closeCode} {
            if {[dict exists $closeOptions -errorcode]} {
                set errorCode [dict get $closeOptions -errorcode]
                if {[lindex $errorCode 0] eq "CHILDSTATUS"} {
                    set exitCode [lindex $errorCode 2]
                }
            }
            set text [string trim $text]
            if {$text eq ""} {
                set text $closeMessage
            }
        }
        set text [string trimright $text "\n"]
        set status [expr {$closeCode ? "failed" : "exited"}]
        if {$terminationReason eq "timeout"} {
            set status timeout
            set exitCode ""
        } elseif {$overflow} {
            set status output_limit
            set exitCode ""
        } elseif {$terminationReason eq "cancelled"} {
            set status cancelled
            set exitCode ""
        }
        return [dict create \
            status $status \
            exit_code $exitCode \
            output $text \
            duration_ms $durationMs \
            timed_out [expr {$status eq "timeout"}] \
            output_truncated $overflow]
    }

    method collectOutput {} {
        if {[catch {read $channel 4096} chunk]} {
            my terminate read-error
            return
        }
        append output $chunk
        if {[string length $output] > $activeMaxOutput} {
            set output [string range $output 0 \
                [expr {$activeMaxOutput - 1}]]
            set overflow 1
            my terminate output-limit
            return
        }
        if {[eof $channel]} {
            fileevent $channel readable {}
            set done 1
        }
    }

    method terminate {reason} {
        if {$done} {
            return
        }
        set terminationReason $reason
        foreach processId $processIds {
            if {$::tcl_platform(platform) eq "windows"} {
                catch {exec taskkill /PID $processId /T /F}
            } else {
                catch {exec kill -KILL -- $processId}
            }
        }
        fileevent $channel readable {}
        set done 1
    }

    method cancel {} {
        if {$channel ne "" && !$done} {
            my terminate cancelled
        }
        return
    }

    method decodeOutput {bytes} {
        if {[catch {encoding convertfrom utf-8 $bytes} text]} {
            error "Runner output is not valid UTF-8"
        }
        return $text
    }
}
