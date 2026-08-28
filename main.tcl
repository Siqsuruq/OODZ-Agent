#!/usr/bin/env tclsh
const version 1.0.0
set scriptDir [file dirname [file normalize [info script]]]
lappend auto_path [file join $scriptDir lib]

package require inifile
package require tLogger
package require tConfClass
package require TclOO
package require tls
package require fileutil
package require zesty

set ::tclReadlineAvailable [expr {![catch {package require tclreadline 2.4}]}]

source [file join $scriptDir clientClass.tcl]
source [file join $scriptDir agentClass.tcl]
source [file join $scriptDir pluginWorker.tcl]
source [file join $scriptDir pluginRegistry.tcl]
source [file join $scriptDir conversationStore.tcl]
source [file join $scriptDir skillRegistry.tcl]
source [file join $scriptDir instructionRegistry.tcl]
source [file join $scriptDir processRunner.tcl]

proc ::usage {} {
    return "Usage: tclsh main.tcl ?task?"
}

proc ::buildAgentSystemRole {
    config workspaceInstructions {skillSummaries {}} {hierarchicalInstructions 0}
    {runnerEnabled 0} {pluginLazyLoading 0}
} {
    set systemRole [$config get Agent.role]
    if {$workspaceInstructions ne ""} {
        append systemRole "\n\nProject workspace instructions:\n" $workspaceInstructions
    }
    append systemRole \
        "\nCall at most one tool in each response." \
        " Never request multiple tools in parallel." \
        " For coding tasks, make at most three read-only inspection" \
        " calls before you either implement, provide the answer, or ask one concise clarification question." \
        " Do not keep searching for examples after you have enough information to follow the framework conventions." \
        " Project workspace instructions are already present in this system message; do not read their file again with a tool." \
        " If an essential detail such as the destination filename is missing, ask the user instead of performing more research."
    if {[llength $skillSummaries] > 0} {
        append systemRole "\n\nAvailable skills (name - trigger description):"
        foreach summary $skillSummaries {
            append systemRole "\n- [dict get $summary name] - " [dict get $summary description]
        }
        append systemRole \
            "\nWhen a skill clearly matches the task, call load_skill once before following that workflow. Do not load unrelated skills."
    }
    if {$hierarchicalInstructions} {
        append systemRole \
            "\nBefore modifying a file below the workspace root, call" \
            " load_project_instructions with that target path once." \
            " Additional instructions are returned from shallowest to" \
            " closest directory;" \
            " closer instructions refine earlier project conventions for" \
            " their subtree, but cannot override safety constraints."
    }
    if {$runnerEnabled} {
        append systemRole \
            "\nAfter creating or modifying a standalone Tcl file, use run_tcl_file when execution is appropriate." \
            " Never claim code was tested unless the runner succeeds."
    }
    if {$pluginLazyLoading} {
        append systemRole \
            "\nOnly core and previously activated plugins are initially available." \
            " When the task needs another capability, call search_plugins with concise capability words." \
            " Matching plugins are activated for your next response."
    }
    return $systemRole
}

proc ::parsePluginNames {configuredNames} {
    set names {}
    foreach configuredName [split $configuredNames ,] {
        set configuredName [string trim $configuredName]
        if {$configuredName ne "" && $configuredName ni $names} {
            lappend names $configuredName
        }
    }
    return $names
}

proc ::resolveWorkspaceRoot {scriptDir configuredRoot} {
    set configuredRoot [string trim $configuredRoot]
    if {$configuredRoot eq ""} {
        error "Workspace.root must not be empty"
    }
    if {[file pathtype $configuredRoot] eq "absolute"} {
        set workspaceRoot [file normalize $configuredRoot]
    } else {
        set workspaceRoot [file normalize [file join $scriptDir $configuredRoot]]
    }
    if {![file isdirectory $workspaceRoot]} {
        error "Workspace.root is not a directory: $configuredRoot"
    }
    return $workspaceRoot
}

proc ::resolvePluginDirectories {scriptDir configuredDirectories} {
    set directories [list [file normalize [file join $scriptDir plugins]]]
    foreach configuredDirectory [split $configuredDirectories ,] {
        set configuredDirectory [string trim $configuredDirectory]
        if {$configuredDirectory eq ""} {
            continue
        }
        if {[file pathtype $configuredDirectory] eq "absolute"} {
            set directory [file normalize $configuredDirectory]
        } else {
            set directory [file normalize [file join $scriptDir $configuredDirectory]]
        }
        if {![file isdirectory $directory]} {
            error "Plugin directory does not exist: $configuredDirectory"
        }
        if {$directory ni $directories} {
            lappend directories $directory
        }
    }
    return $directories
}

proc ::resolveSkillDirectories {scriptDir configuredDirectories} {
    set directories [list [file normalize [file join $scriptDir skills]]]
    foreach configuredDirectory [split $configuredDirectories ,] {
        set configuredDirectory [string trim $configuredDirectory]
        if {$configuredDirectory eq ""} {
            continue
        }
        if {[file pathtype $configuredDirectory] eq "absolute"} {
            set directory [file normalize $configuredDirectory]
        } else {
            set directory [file normalize [file join $scriptDir $configuredDirectory]]
        }
        if {![file isdirectory $directory]} {
            error "Skill directory does not exist: $configuredDirectory"
        }
        if {$directory ni $directories} {
            lappend directories $directory
        }
    }
    return $directories
}

proc ::loadWorkspaceInstructions {
    workspaceRoot configuredPath {maximumBytes 16384}
} {
    set configuredPath [string trim $configuredPath]
    if {$configuredPath eq ""} {
        return ""
    }
    if {[file pathtype $configuredPath] ne "relative"} {
        error "Workspace.instructions must be relative to the workspace"
    }

    set path [file normalize [file join $workspaceRoot $configuredPath]]
    if {![::PluginSupport::isWithin $path $workspaceRoot]} {
        error "Workspace instruction file escapes the workspace"
    }
    if {![file isfile $path]} {
        error "Workspace instruction file does not exist: $configuredPath"
    }
    set size [file size $path]
    if {$size > $maximumBytes} {
        error "Workspace instruction file exceeds $maximumBytes bytes: $configuredPath"
    }

    set channel [open $path rb]
    try {
        set bytes [read $channel]
    } finally {
        close $channel
    }
    if {[catch {encoding convertfrom utf-8 $bytes} instructions]} {
        error "Workspace instruction file is not valid UTF-8: $configuredPath"
    }
    return [string trimleft $instructions \ufeff]
}

proc ::resolveOptionalReferenceRoot {scriptDir configuredRoot settingName} {
    set configuredRoot [string trim $configuredRoot]
    if {$configuredRoot eq ""} {
        return ""
    }
    if {[file pathtype $configuredRoot] eq "absolute"} {
        set root [file normalize $configuredRoot]
    } else {
        set root [file normalize [file join $scriptDir $configuredRoot]]
    }
    if {![file isdirectory $root]} {
        error "$settingName is not a directory: $configuredRoot"
    }
    return $root
}

proc ::terminalStyleEnabled {channel} {
    if {$channel ni {stdout stderr}} {
        return 0
    }
    if {[info exists ::env(NO_COLOR)]} {
        return 0
    }
	
	if {$::tcl_platform(platform) eq "windows"} {
        # Windows: Use TWAPI to check if channel is a real console. Try to load twapi if not already loaded
        if {[catch {package require twapi}] == 0} {
            # Check if channel is redirected, get_tcl_channel_handle succeeds for real consoles, fails for redirects
            if {[catch {twapi::get_tcl_channel_handle $channel write}]} {
                # Failed = redirected (file/pipe) = no colors
                return 0
            } else {
                # Succeeded = real console = colors supported
                return 1
            }
        } else {
            # twapi not available - fallback to environment detection
            if {[info exists ::env(WT_SESSION)] || [info exists ::env(ConEmuPID)]} {
                return 1
            }
            # Default assumption for Windows
            return 1
        }
    }
	
    # Tcl exposes terminal-only channel options such as -mode for a real TTY.
    # Pipes and regular files reject this option.
    if {[catch {fconfigure $channel -mode}]} {
        return 0
    }
    expr {
        [info exists ::env(TERM)]
        && $::env(TERM) ne ""
        && $::env(TERM) ne "dumb"
    }
}

proc ::styleTerminalText {channel text style} {
    if {![::terminalStyleEnabled $channel]} {
        return $text
    }
    return [zesty::parseStyle $text $style]
}

proc ::configureStandardChannels {} {
	puts "Configuring channels"
	if {$::tcl_platform(platform) eq "windows"} {
		#puts "we are here"
		# Set console to UTF-8
		catch {exec chcp.com 65001 > nul}
		# BUT don't change stdout encoding - let Tcl use its Windows Unicode handler
		# Only set stdin if you need to read UTF-8 input
		#catch {fconfigure stdin -encoding utf-8}
	} else {
		# On Unix/Linux/macOS, UTF-8 everywhere is fine
		foreach channel {stdin stdout stderr} {
			#puts "channel : $channel"
			catch {fconfigure $channel -encoding utf-8}
		}
	}
}

proc ::printInteractiveBanner {outputChannel} {
    if {![::terminalStyleEnabled $outputChannel]} {
        puts $outputChannel "OODZ Agent - interactive mode"
        puts $outputChannel "Type /help for commands."
        return
    }

    set boxType [expr {$::tcl_platform(platform) eq "windows" ? "ascii" : "rounded"}]
    set banner [zesty::box -title {name "OODZ Agent" anchor "nw" style {fg cyan bold 1}} -content {text "Tcl coding agent\nType /help for commands."} -box [list type $boxType style {fg cyan}] -paddingX 1]
    puts $outputChannel [zesty::parseStyle $banner {}]
}

proc ::requestPluginApproval {inputChannel outputChannel name arguments} {
    if {![info exists ::approveAllWritesForSession]} {
        set ::approveAllWritesForSession 0
    }
    if {$::approveAllWritesForSession
            && $name ni {run_tcl_file run_project_tests}} {
        return 1
    }
    set target ""
    if {[dict exists $arguments path]} {
        set target " ([dict get $arguments path])"
    } elseif {[dict exists $arguments original]} {
        set target " ([dict get $arguments original])"
    }
    if {$name in {run_tcl_file run_project_tests}} {
        set action [expr {$name eq "run_tcl_file"
            ? "Tcl file$target"
            : "configured project tests"}]
        set prompt "Execute $action? No OS sandbox may be active; code can use your account permissions. \[y/N\] "
    } else {
        set prompt "Allow write plugin '$name'$target? \[y/N/all for session\] "
    }
    set styledPrompt [::styleTerminalText $outputChannel $prompt {fg yellow bold 1}]
    lassign [::readInteractiveLine $inputChannel $outputChannel $styledPrompt] readCount answer
    if {$readCount < 0} {
        puts $outputChannel ""
        return 0
    }
    set answer [string tolower [string trim $answer]]
    if {$name ni {run_tcl_file run_project_tests}
            && $answer in {a all}} {
        set ::approveAllWritesForSession 1
        return 1
    }
    expr {$answer in {y yes}}
}

proc ::printStreamChunk {outputChannel chunk} {
    puts -nonewline $outputChannel [::styleTerminalText $outputChannel $chunk {fg 117}]
    flush $outputChannel
}

proc ::printConversationSeparator {outputChannel} {
    if {![::terminalStyleEnabled $outputChannel]} {
        return
    }
    set character [expr {$::tcl_platform(platform) eq "windows" ? "-" : "─"}]
    puts $outputChannel [::styleTerminalText $outputChannel [string repeat $character 56] {fg 60 dim 1}]
}

proc ::readRecentLog {path {lineLimit 20}} {
    if {$path eq "" || ![file exists $path]} {
        return "(no log entries)"
    }
    set channel [open $path r]
    try {
        fconfigure $channel -encoding utf-8
        set lines [split [string trimright [read $channel] "\n"] "\n"]
    } finally {
        close $channel
    }
    return [join [lrange $lines end-[expr {$lineLimit - 1}] end] "\n"]
}

proc ::readInteractiveLine {inputChannel outputChannel prompt} {
    if {$::tclReadlineAvailable && $inputChannel eq "stdin" && $outputChannel in {stdout stderr} && [::terminalStyleEnabled $outputChannel]} {
        if {[catch {
            ::tclreadline::readline read $prompt
        } line]} {
            return [list -1 ""]
        }
        return [list [string length $line] $line]
    }

    puts -nonewline $outputChannel $prompt
    flush $outputChannel
    set line ""
    return [list [gets $inputChannel line] $line]
}

proc ::runInteractive {
    agent pluginRegistry skillRegistry historyStore logPath \
    inputChannel outputChannel errorChannel
} {
    ::printInteractiveBanner $outputChannel

    while 1 {
        set prompt [::styleTerminalText $outputChannel "you> " {fg 213 bold 1}]
        lassign [::readInteractiveLine $inputChannel $outputChannel $prompt] readCount line
        if {$readCount < 0} {
            return 0
        }

        set line [string trim $line]
        if {$line eq ""} {
            continue
        }

        if {$line eq "/multi"} {
            puts $outputChannel [::styleTerminalText $outputChannel "Multiline mode: /send submits, /cancel aborts." {fg cyan}]
            set multilineLines {}
            set multilineCancelled 0
            while 1 {
                set continuationPrompt [::styleTerminalText $outputChannel "...> " {fg 213}]
                lassign [::readInteractiveLine \
                    $inputChannel $outputChannel $continuationPrompt] multilineCount multilineLine
                if {$multilineCount < 0} {
                    return 0
                }
                set multilineCommand [string trim $multilineLine]
                if {$multilineCommand eq "/send"} {
                    break
                }
                if {$multilineCommand eq "/cancel"} {
                    set multilineCancelled 1
                    break
                }
                lappend multilineLines $multilineLine
            }
            if {$multilineCancelled} {
                puts $outputChannel [::styleTerminalText $outputChannel "Multiline input cancelled." {fg yellow}]
                continue
            }
            if {[llength $multilineLines] == 0} {
                puts $errorChannel [::styleTerminalText $errorChannel "Multiline input is empty." {fg red}]
                continue
            }
            set line [join $multilineLines "\n"]
        }

        if {[regexp {^/oodz_trns(?:[[:space:]]+(.*))?$} $line -> translationLabel]} {
            if {![info exists translationLabel] || [string trim $translationLabel] eq ""} {
                puts $errorChannel [::styleTerminalText $errorChannel "Usage: /oodz_trns label" {fg red}]
                continue
            }
            set translationLabel [string trim $translationLabel]
            set line [join [list "Translate the label '$translationLabel' into native-script" "Portuguese, Simplified Chinese, Russian, French, Spanish," "and English, then save it using save_translation." "Never transliterate any language."] " "]
        }

        if {[regexp {^/tool(?:[[:space:]]|$)} $line]} {
            set invocation [string trim [string range $line 5 end]]
            if {$invocation eq ""} {
                puts $errorChannel [::styleTerminalText $errorChannel "Usage: /tool name ?JSON arguments?" {fg red}]
                continue
            }
            if {![regexp {^(\S+)(?:[[:space:]]+(.*))?$} $invocation -> toolName toolArguments]} {
                puts $errorChannel [::styleTerminalText $errorChannel "Usage: /tool name ?JSON arguments?" {fg red}]
                continue
            }
            if {![info exists toolArguments] || [string trim $toolArguments] eq ""} {
                set toolArguments "{}"
            }
            if {[catch {
                $pluginRegistry invoke $toolName $toolArguments
            } toolResult]} {
                puts $errorChannel [::styleTerminalText $errorChannel "Tool error: $toolResult" {fg red bold 1}]
                continue
            }
            puts $outputChannel $toolResult
            continue
        }

        switch -- $line {
            /exit - /quit {
                return 0
            }
            /help {
                puts $outputChannel [::styleTerminalText $outputChannel \
                    "/help /multi /tools /skills /tool name ?JSON? /oodz_trns label /history /logs /new /exit" \
                    {fg cyan}]
            }
            /tools {
                puts $outputChannel [::styleTerminalText $outputChannel \
                    [join [$pluginRegistry names] ", "] {fg green}]
            }
            /skills {
                foreach summary [$skillRegistry summaries] {
                    puts $outputChannel [::styleTerminalText $outputChannel \
                        "[dict get $summary name] - [dict get $summary description]" \
                        {fg 117}]
                }
            }
            /history {
                set history [$agent getHistory]
                if {[llength $history] == 0} {
                    puts $outputChannel "(empty)"
                    continue
                }
                foreach message $history {
                    set role [dict get $message role]
                    set content ""
                    if {[dict exists $message content]} {
                        set content [dict get $message content]
                    }
                    set historyStyle [expr {$role eq "user" ? {fg 213 bold 1} : {fg 117}}]
                    puts $outputChannel [::styleTerminalText $outputChannel "$role> $content" $historyStyle]
                }
            }
            /logs {
                puts $outputChannel [::readRecentLog $logPath]
            }
            /new {
                $agent clearHistory
                if {$historyStore ne ""} {
                    $historyStore clear
                }
                puts $outputChannel [::styleTerminalText $outputChannel "Started a new conversation." {fg green}]
            }
            default {
                if {[string index $line 0] eq "/"} {
                    puts $errorChannel [::styleTerminalText $errorChannel "Unknown command: $line (use /help)" {fg red}]
                    continue
                }
                ::printConversationSeparator $outputChannel
                if {[catch {$agent run $line} response]} {
                    puts $errorChannel [::styleTerminalText $errorChannel "Error: $response" {fg red bold 1}]
                    if {$historyStore ne "" && [catch { $historyStore saveState [$agent getHistoryState] } historyError]} {
                        puts $errorChannel [::styleTerminalText $errorChannel "History error: $historyError" {fg red}]
                    }
                    continue
                }
                if {[$agent usesStreaming]} {
                    flush $outputChannel
                } else {
                    puts $outputChannel [::styleTerminalText $outputChannel $response {fg 117}]
                }
                if {$historyStore ne "" && [catch { $historyStore saveState [$agent getHistoryState] } historyError]} {
                    puts $errorChannel [::styleTerminalText $errorChannel "History error: $historyError" {fg red}]
                }
            }
        }
    }
}

proc ::main {scriptDir arguments {clientObject ""} {outChannel stdout} {errChannel stderr} {inChannel stdin} {historyPathOverride ""}} {
    if {[llength $arguments] == 1 && [lindex $arguments 0] in {-h --help}} {
        puts $outChannel [::usage]
        return 0
    }
    set interactive [expr {[llength $arguments] == 0}]
    set ::approveAllWritesForSession 0

    set config ""
    set backend ""
    set aiEngine $clientObject
    set codingAgent ""
    set pluginRegistry ""
    set skillRegistry ""
    set instructionRegistry ""
    set processRunner ""
    set pluginWorker ""
    set historyStore ""
    set logPath ""
    set ownsClient [expr {$clientObject eq ""}]
    set productionLogging [expr {$ownsClient && $outChannel eq "stdout" && $errChannel eq "stderr" }]
    try {
        set config [::Config new]
        set backend [::Config::Backend::Ini new]
        $config useBackend $backend [file join $scriptDir conf conf.ini]
        $config load

        if {$productionLogging} {
            set logPath [$config get Logging.file .oodz/oodz.log]
            if {[file pathtype $logPath] ne "absolute"} {
                set logPath [file join $scriptDir $logPath]
            }
            file mkdir [file dirname $logPath]
            ::tLogger setAppenderFactory [list ::FileAppender new $logPath]
            catch {file attributes $logPath -permissions 0600}
        }
        set globalLog [::tLogger getLogger "Global"]
        $globalLog setLogLevel [$config get Logging.level info]

        set workspaceRoot [::resolveWorkspaceRoot $scriptDir [$config get Workspace.root .]]
        set workspaceInstructions [::loadWorkspaceInstructions $workspaceRoot [$config get Workspace.instructions ""] [$config get Workspace.instructions_max_file_bytes 16384]]
        set referenceRoots [dict create]
        set oodzRoot [::resolveOptionalReferenceRoot $scriptDir [$config get OODZ.root ""] OODZ.root]
        if {$oodzRoot ne ""} {
            dict set referenceRoots oodz $oodzRoot
        }

        if {$ownsClient} {
            set aiEngine [tLLMClient new $config]
        }
        set skillRegistry [tSkillRegistry new [::resolveSkillDirectories $scriptDir [$config get Skills.directories ""]] [$config get Skills.max_file_bytes 65536]]
        set instructionRegistry [tInstructionRegistry new $workspaceRoot [$config get Workspace.instructions ""] [$config get Workspace.instructions_max_file_bytes 16384] [$config get Workspace.instructions_max_total_bytes 65536]]
        set runnerEnabled [$config get Runner.enabled false]
        if {![string is boolean -strict $runnerEnabled]} {
            error "Runner.enabled must be boolean"
        }
        set projectTestsEnabled false
        if {$runnerEnabled} {
            set processRunner [tProcessRunner new $workspaceRoot \
                [$config get Runner.tclsh tclsh9.0] \
                [$config get Runner.timeout_ms 10000] \
                [$config get Runner.max_output_chars 65536] "" \
                [dict create fossil [$config get Executables.fossil fossil]]]
            set projectTestsEnabled [$config get Runner.project_tests_enabled false]
            if {![string is boolean -strict $projectTestsEnabled]} {
                error "Runner.project_tests_enabled must be boolean"
            }
            if {$projectTestsEnabled} {
                $processRunner configureProjectTests [$config get Runner.project_tests_executable ""] [$config get Runner.project_tests_arguments ""] [$config get Runner.project_tests_timeout_ms 60000]
            }
        }
        set pluginLazyLoading [$config get Plugins.lazy_loading true]
        if {![string is boolean -strict $pluginLazyLoading]} {
            error "Plugins.lazy_loading must be boolean"
        }
        set pluginCore [::parsePluginNames [$config get Plugins.core \
            "read_file,list_files,search_files,file_info,apply_patch,write_file"]]
        set pluginDirectories [::resolvePluginDirectories $scriptDir \
            [$config get Plugins.directories ""]]
        set workerEnabled [$config get Plugins.worker_thread true]
        if {![string is boolean -strict $workerEnabled]} {
            error "Plugins.worker_thread must be boolean"
        }
        if {$workerEnabled} {
            set runnerConfig [dict create \
                enabled $runnerEnabled \
                tclsh [$config get Runner.tclsh tclsh9.0] \
                timeout_ms [$config get Runner.timeout_ms 10000] \
                max_output_chars [$config get Runner.max_output_chars 65536] \
                executable_aliases [dict create fossil \
                    [$config get Executables.fossil fossil]] \
                project_tests_enabled $projectTestsEnabled \
                project_tests_executable \
                    [$config get Runner.project_tests_executable tclsh9.0] \
                project_tests_arguments \
                    [$config get Runner.project_tests_arguments tests/all.tcl] \
                project_tests_timeout_ms \
                    [$config get Runner.project_tests_timeout_ms 60000]]
            set pluginWorker [tPluginWorker new \
                $scriptDir $workspaceRoot $pluginDirectories \
                [$config get Plugins.timeout_ms 1000] \
                [$config get Plugins.max_output_chars 65536] \
                $referenceRoots $runnerConfig]
        }
        set pluginRegistry [tPluginRegistry new $workspaceRoot $pluginDirectories [list ::requestPluginApproval $inChannel $errChannel] [$config get Plugins.timeout_ms 1000] [$config get Plugins.max_output_chars 65536] $referenceRoots $skillRegistry $instructionRegistry $processRunner $pluginLazyLoading $pluginCore "" $pluginWorker]
        set systemRole [::buildAgentSystemRole $config $workspaceInstructions [$skillRegistry summaries] [$instructionRegistry enabled] $runnerEnabled $pluginLazyLoading]
        set codingAgent [tAgent new [$config get Agent.name] $systemRole $aiEngine $pluginRegistry [$config get Agent.max_iterations 16] [expr {$interactive ? [list ::printStreamChunk $outChannel] : ""}] [$config get Agent.max_history_messages 40] [$config get Agent.summarize_history false]]

        if {$interactive} {
            set readlineHistoryPath ""
            if {$::tclReadlineAvailable && $inChannel eq "stdin" && $outChannel eq "stdout" && [::terminalStyleEnabled $outChannel]} {
                set readlineHistoryPath [file join $scriptDir .oodz readline-history]
                file mkdir [file dirname $readlineHistoryPath]
                if {[catch {
                    ::tclreadline::readline initialize $readlineHistoryPath
                } readlineError]} {
                    set ::tclReadlineAvailable 0
                    $globalLog log warn "tclreadline initialization failed: $readlineError"
                } else {
                    set ::tclreadline::historyLength 200
                }
            }
            if {$ownsClient || $historyPathOverride ne ""} {
                set historyPath $historyPathOverride
                if {$historyPath eq ""} {
                    set historyPath [$config get Agent.history_file .oodz/history.json]
                }
                if {[file pathtype $historyPath] ne "absolute"} {
                    set historyPath [file join $scriptDir $historyPath]
                }
                set historyStore [tConversationStore new $historyPath]
                $codingAgent replaceHistoryState [$historyStore loadState]
            }
            try {
                return [::runInteractive $codingAgent $pluginRegistry $skillRegistry $historyStore $logPath $inChannel $outChannel $errChannel]
            } finally {
                if {$readlineHistoryPath ne ""} {
                    catch {::tclreadline::readline write $readlineHistoryPath}
                    catch {file attributes $readlineHistoryPath -permissions 0600}
                }
            }
        } else {
            set result [$codingAgent run [join $arguments " "]]
            puts $outChannel $result
            return 0
        }
    } on error {message options} {
        puts $errChannel "Error: $message"
        return 1
    } finally {
        foreach object [list $codingAgent] {
            if {$object ne "" && [info object isa object $object]} {
                $object destroy
            }
        }
        if {$ownsClient
                && $aiEngine ne ""
                && [info object isa object $aiEngine]} {
            $aiEngine destroy
        }
        foreach object [list $historyStore $pluginRegistry $pluginWorker \
                $instructionRegistry $skillRegistry $processRunner \
                $backend $config] {
            if {$object ne "" && [info object isa object $object]} {
                $object destroy
            }
        }
    }
}

if {[info exists ::argv0] && [file normalize [info script]] eq [file normalize $::argv0]} {
    ::configureStandardChannels
    exit [::main $scriptDir $::argv]
}
