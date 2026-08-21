::oo::class create tProcessRunner {
    variable workspaceRoot tclExecutable backend sandboxExecutable
    variable timeoutMs maxOutput executor channel output done overflow
    variable processIds watchdog terminationReason
    variable projectTestsEnabled projectTestsExecutable
    variable projectTestsArguments projectTestsTimeout

    constructor {
        configuredWorkspaceRoot configuredTclExecutable configuredBackend
        configuredSandboxExecutable configuredTimeoutMs configuredMaxOutput
        {configuredExecutor ""}
    } {
        set workspaceRoot [file normalize $configuredWorkspaceRoot]
        if {![file isdirectory $workspaceRoot]} {
            error "Runner workspace root is not a directory"
        }
        set tclExecutable [my resolveExecutable \
            $configuredTclExecutable "Runner.tclsh"]
        set backend [string tolower [string trim $configuredBackend]]
        if {$backend ni {direct bubblewrap}} {
            error "Runner.backend must be one of: direct, bubblewrap"
        }
        set sandboxExecutable ""
        if {$backend eq "bubblewrap"} {
            set sandboxExecutable [my resolveExecutable \
                $configuredSandboxExecutable "Runner.sandbox"]
        }
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
        set executor $configuredExecutor
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
        return $backend
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
        set command [my wrapCommand \
            [list $projectTestsExecutable {*}$projectTestsArguments] \
            $projectTestsTimeout]
        if {$executor ne ""} {
            return [{*}$executor $command $projectTestsTimeout $maxOutput]
        }
        return [my execute $command $projectTestsTimeout]
    }

    method runConfiguredCommand {configuredExecutable arguments} {
        if {[catch {llength $arguments}]} {
            error "Configured command arguments must be a valid Tcl list"
        }
        set executable [my resolveExecutable \
            $configuredExecutable "Plugin executable"]
        set command [my wrapCommand \
            [list $executable {*}$arguments] $timeoutMs]
        if {$executor ne ""} {
            return [{*}$executor $command $timeoutMs $maxOutput]
        }
        return [my execute $command]
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

        set scriptPath [expr {$backend eq "direct"
            ? $path
            : [file join /workspace $relativePath]}]
        return [my wrapCommand \
            [list $tclExecutable $scriptPath] $timeoutMs]
    }

    method wrapCommand {profileCommand executionTimeout} {
        if {$backend eq "direct"} {
            return $profileCommand
        }
        set command [list \
            $sandboxExecutable \
            --die-with-parent \
            --unshare-all \
            --new-session \
            --ro-bind /usr /usr]
        foreach runtimeRoot {/lib /lib64} {
            if {[file exists $runtimeRoot]} {
                lappend command --ro-bind $runtimeRoot $runtimeRoot
            }
        }
        if {[file isfile /etc/ld.so.cache]} {
            lappend command \
                --dir /etc \
                --ro-bind /etc/ld.so.cache /etc/ld.so.cache
        }
        lappend command \
            --dev /dev \
            --proc /proc \
            --tmpfs /tmp \
            --bind $workspaceRoot /workspace \
            --chdir /workspace \
            /usr/bin/timeout \
            --kill-after=1 \
            [format %.3f [expr {$executionTimeout / 1000.0}]] \
            {*}$profileCommand
        return $command
    }

    method execute {command {executionTimeout ""}} {
        if {$executionTimeout eq ""} {
            set executionTimeout $timeoutMs
        }
        set output ""
        set done 0
        set overflow 0
        set terminationReason ""
        set pipeline [concat [list |] $command [list 2>@1]]
        set previousDirectory [pwd]
        try {
            cd $workspaceRoot
            set channel [open $pipeline r]
        } finally {
            cd $previousDirectory
        }
        fconfigure $channel \
            -blocking 0 -translation binary -encoding iso8859-1
        set processIds [pid $channel]
        fileevent $channel readable [list [self] collectOutput]
        set watchdogDelay [expr {$backend eq "direct"
            ? $executionTimeout
            : $executionTimeout + 2000}]
        set watchdog [after $watchdogDelay \
            [list [self] terminate timeout]]
        vwait [namespace which -variable done]
        after cancel $watchdog

        set closeCode [catch {close $channel} closeMessage closeOptions]
        set channel ""
        if {$overflow} {
            error "Runner output exceeds limit"
        }
        if {$terminationReason eq "timeout"} {
            error "Runner timed out after $executionTimeout ms"
        }
        set text [my decodeOutput $output]
        if {$closeCode} {
            if {[dict exists $closeOptions -errorcode]} {
                set errorCode [dict get $closeOptions -errorcode]
                if {[lindex $errorCode 0] eq "CHILDSTATUS"
                        && [lindex $errorCode 2] in {124 137}} {
                    error "Runner timed out after $timeoutMs ms"
                }
            }
            set text [string trim $text]
            if {$text eq ""} {
                set text $closeMessage
            }
            error "Tcl process failed: $text"
        }
        set text [string trimright $text "\n"]
        expr {$text eq "" ? "(process completed with no output)" : $text}
    }

    method collectOutput {} {
        if {[catch {read $channel 4096} chunk]} {
            my terminate read-error
            return
        }
        append output $chunk
        if {[string length $output] > $maxOutput} {
            set output [string range $output 0 [expr {$maxOutput - 1}]]
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

    method decodeOutput {bytes} {
        if {[catch {encoding convertfrom utf-8 $bytes} text]} {
            error "Runner output is not valid UTF-8"
        }
        return $text
    }
}
