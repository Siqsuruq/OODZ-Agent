#!/usr/bin/env wish


namespace eval ::oodzGui {
    variable scriptDir [file dirname [file normalize [info script]]]
    variable agent ""
    variable client ""
    variable registry ""
    variable skillRegistry ""
    variable instructionRegistry ""
    variable processRunner ""
    variable pluginWorker ""
    variable config ""
    variable backend ""
    variable historyStore ""
    variable approveAll 0
    variable approvalResult 0
    variable busy 0
    variable toolDefinitions [dict create]
    variable contextWidget ""
    variable darkTheme 0
	variable streamCount 0
}
source [file join $::oodzGui::scriptDir main.tcl]
lappend ::auto_path [file join $::oodzGui::scriptDir lib oodzMarkdownTk]
package require oodzMarkdownTk 0.1.0
package require Tk 9.0

proc ::oodzGui::appendMessage {role content} {
    .conversation configure -state normal
    if {$role ne ""} {
        .conversation insert end "$role\n" "${role}Label"
    }
    if {$role eq "Assistant"} {
        ::oodzMarkdownTk::render .conversation $content assistant
        .conversation insert end "\n"
    } else {
        .conversation insert end "$content\n\n" $role
    }
    .conversation configure -state disabled
    .conversation see end
    update idletasks
}

proc ::oodzGui::streamChunk {chunk} {
    variable streamCount
    incr streamCount
    ::oodzMarkdownTk::append .conversation $chunk
    .conversation see end
    update idletasks
}

proc ::oodzGui::approvalChoice {choice} {
    variable approvalResult
    set approvalResult $choice
}

proc ::oodzGui::approve {name arguments} {
    variable approveAll
    variable approvalResult
    if {$approveAll && $name ni {run_tcl_file run_project_tests}} {
        return 1
    }
    set target ""
    if {[dict exists $arguments path]} {
        set target "\n[dict get $arguments path]"
    } elseif {[dict exists $arguments original]} {
        set target "\n[dict get $arguments original]"
    }
    set approvalResult -1
    catch {destroy .approval}
    toplevel .approval
    wm title .approval "Approve write tool"
    wm transient .approval .
    wm minsize .approval 460 150
    wm resizable .approval 1 0
    if {$name in {run_tcl_file run_project_tests}} {
        set action [expr {$name eq "run_tcl_file"
            ? "Tcl file$target"
            : "configured project tests"}]
        set message "Execute $action?\n\nWARNING: No OS sandbox may be active. The code can use your account permissions."
    } else {
        set message "Allow write plugin '$name'?$target"
    }
    ttk::label .approval.message -text $message -justify left
    ttk::button .approval.yes -text "Yes" -command [list ::oodzGui::approvalChoice 1]
    if {$name ni {run_tcl_file run_project_tests}} {
        ttk::button .approval.all -text "All for session" -command [list ::oodzGui::approvalChoice 2]
    }
    ttk::button .approval.no -text "Deny" -command [list ::oodzGui::approvalChoice 0]
    grid .approval.message -row 0 -column 0 -columnspan 3 -sticky nsew -padx 16 -pady {16 20}
    grid .approval.yes -row 1 -column 0 -padx {16 4} -pady {0 16} -sticky ew
    if {$name ni {run_tcl_file run_project_tests}} {
        grid .approval.all -row 1 -column 1 -padx 4 -pady {0 16} -sticky ew
    }
    grid .approval.no -row 1 -column 2 -padx {4 16} -pady {0 16} -sticky ew
    grid rowconfigure .approval 0 -weight 1
    foreach column {0 1 2} {
        grid columnconfigure .approval $column -weight 1
    }
    wm protocol .approval WM_DELETE_WINDOW [list ::oodzGui::approvalChoice 0]
    tkwait visibility .approval
    grab set .approval
    focus .approval.yes
    tkwait variable ::oodzGui::approvalResult
    grab release .approval
    destroy .approval
    if {$approvalResult == 2} {
        set approveAll 1
        return 1
    }
    expr {$approvalResult == 1}
}

proc ::oodzGui::saveHistory {} {
    variable agent
    variable historyStore
    if {$historyStore ne ""} {
        $historyStore saveState [$agent getHistoryState]
    }
}

proc ::oodzGui::renderHistory {} {
    variable agent
    foreach message [$agent getHistory] {
        if {![dict exists $message content] || [string trim [dict get $message content]] eq ""} {
            continue
        }
        set role [dict get $message role]
        if {$role ni {user assistant}} {
            continue
        }
        ::oodzGui::appendMessage [expr {$role eq "user" ? "You" : "Assistant"}] [dict get $message content]
    }
}

proc ::oodzGui::send {} {
    variable agent
    variable busy
    if {$busy} {
        return
    }
    set task [string trim [.input get 1.0 end-1c]]
    if {$task eq ""} {
        return
    }
    set busy 1
    .input delete 1.0 end
    .send configure -state disabled
    .status configure -text "Working…"
    ::oodzGui::appendMessage You $task
    .conversation configure -state normal
    .conversation insert end "Assistant\n" assistantLabel
    .conversation configure -state disabled
    ::oodzMarkdownTk::begin .conversation assistant
    update idletasks
    if {[catch {$agent run $task} result]} {
        ::oodzMarkdownTk::finish .conversation
        ::oodzGui::appendMessage Error "Error: $result"
    } else {
        ::oodzMarkdownTk::finish .conversation
        .conversation configure -state normal
        .conversation insert end "\n"
        .conversation configure -state disabled
        .conversation see end
    }
    if {[catch {::oodzGui::saveHistory} historyError]} {
        ::oodzGui::appendMessage Error "History error: $historyError"
    }
    set busy 0
    .send configure -state normal
    .status configure -text "Ready"
    focus .input
}

proc ::oodzGui::newConversation {} {
    variable agent
    variable historyStore
    variable busy
    if {$busy} {
        return
    }
    $agent clearHistory
    if {$historyStore ne ""} {
        $historyStore clear
    }
    .conversation configure -state normal
    .conversation delete 1.0 end
    .conversation configure -state disabled
    .status configure -text "New conversation"
}

proc ::oodzGui::showSkills {} {
    variable skillRegistry
    catch {destroy .skills}
    toplevel .skills
    wm title .skills "Available skills"
    wm transient .skills .
    wm minsize .skills 560 280
    text .skills.list -wrap word -padx 12 -pady 12 -state normal
    ttk::scrollbar .skills.scroll -orient vertical -command [list .skills.list yview]
    .skills.list configure -yscrollcommand [list .skills.scroll set]
    foreach summary [$skillRegistry summaries] {
        .skills.list insert end "[dict get $summary name]\n" name
        .skills.list insert end "[dict get $summary description]\n\n"
    }
    .skills.list tag configure name -font TkHeadingFont
    .skills.list configure -state disabled
    grid .skills.list -row 0 -column 0 -sticky nsew
    grid .skills.scroll -row 0 -column 1 -sticky ns
    grid rowconfigure .skills 0 -weight 1
    grid columnconfigure .skills 0 -weight 1
}

proc ::oodzGui::selectTool {} {
    variable toolDefinitions
    set selection [.tools.left.names curselection]
    if {[llength $selection] != 1} {
        return
    }
    set name [.tools.left.names get [lindex $selection 0]]
    set definition [dict get $toolDefinitions $name]
    .tools.right.description configure -text [dict get $definition description]
    .tools.right.schema configure -state normal
    .tools.right.schema delete 1.0 end
    .tools.right.schema insert end [dict get $definition parameters_json]
    .tools.right.schema configure -state disabled
    .tools.right.arguments delete 1.0 end
    .tools.right.arguments insert end "{}"
    .tools.right.result configure -state normal
    .tools.right.result delete 1.0 end
    .tools.right.result configure -state disabled
    .tools.right.run configure -state normal
}

proc ::oodzGui::runSelectedTool {} {
    variable registry
    variable busy
    set selection [.tools.left.names curselection]
    if {$busy || [llength $selection] != 1} {
        return
    }
    set name [.tools.left.names get [lindex $selection 0]]
    set arguments [string trim [.tools.right.arguments get 1.0 end-1c]]
    if {$arguments eq ""} {
        set arguments "{}"
    }
    set busy 1
    .tools.right.run configure -state disabled
    .status configure -text "Running $name…"
    .tools.right.result configure -state normal
    .tools.right.result delete 1.0 end
    .tools.right.result insert end "Running $name…"
    .tools.right.result configure -state disabled
    update idletasks
    set invocationCode [catch {
        $registry invoke $name $arguments
    } result]
    .tools.right.result configure -state normal
    .tools.right.result delete 1.0 end
    if {$invocationCode} {
        .tools.right.result insert end "Error: $result" error
    } else {
        .tools.right.result insert end $result
    }
    .tools.right.result configure -state disabled
    set busy 0
    .tools.right.run configure -state normal
    .status configure -text "Ready"
}

proc ::oodzGui::showTools {} {
    variable registry
    variable toolDefinitions
    catch {destroy .tools}
    set toolDefinitions [dict create]
    foreach definition [$registry definitions] {
        dict set toolDefinitions [dict get $definition name] $definition
    }

    toplevel .tools
    wm title .tools "Run a tool"
    wm transient .tools .
    wm minsize .tools 760 520

    ttk::frame .tools.left -padding 8
    ttk::frame .tools.right -padding 8
    listbox .tools.left.names -exportselection false -width 24
    ttk::scrollbar .tools.left.namesScroll -orient vertical -command [list .tools.left.names yview]
    .tools.left.names configure -yscrollcommand [list .tools.left.namesScroll set]
    ttk::label .tools.right.description -text "Select a tool" -anchor nw -justify left -wraplength 500
    ttk::label .tools.right.schemaLabel -text "Argument schema"
    text .tools.right.schema -height 5 -wrap word -state disabled -padx 8 -pady 8
    ttk::label .tools.right.argumentsLabel -text "Arguments (JSON)"
    text .tools.right.arguments -height 7 -wrap word -padx 8 -pady 8
    ttk::label .tools.right.resultLabel -text "Result"
    text .tools.right.result -height 10 -wrap word -state disabled -padx 8 -pady 8
    .tools.right.result tag configure error -foreground #c62828
    ttk::button .tools.right.run -text "Run tool" -state disabled -command ::oodzGui::runSelectedTool
    ttk::button .tools.right.close -text "Close" -command [list destroy .tools]

    foreach name [lsort [dict keys $toolDefinitions]] {
        .tools.left.names insert end $name
    }
    grid .tools.left -row 0 -column 0 -sticky nsew
    grid .tools.right -row 0 -column 1 -sticky nsew
    grid .tools.left.names -row 0 -column 0 -sticky nsew
    grid .tools.left.namesScroll -row 0 -column 1 -sticky ns
    grid .tools.right.description -row 0 -column 0 -columnspan 2 -sticky ew -pady {0 10}
    grid .tools.right.schemaLabel -row 1 -column 0 -columnspan 2 -sticky w
    grid .tools.right.schema -row 2 -column 0 -columnspan 2 -sticky nsew -pady {4 10}
    grid .tools.right.argumentsLabel -row 3 -column 0 -columnspan 2 -sticky w
    grid .tools.right.arguments -row 4 -column 0 -columnspan 2 -sticky nsew -pady {4 10}
    grid .tools.right.resultLabel -row 5 -column 0 -columnspan 2 -sticky w
    grid .tools.right.result -row 6 -column 0 -columnspan 2 -sticky nsew -pady {4 10}
    grid .tools.right.run -row 7 -column 0 -sticky w
    grid .tools.right.close -row 7 -column 1 -sticky e
    grid rowconfigure .tools 0 -weight 1
    grid columnconfigure .tools 1 -weight 1
    grid rowconfigure .tools.left 0 -weight 1
    grid columnconfigure .tools.left 0 -weight 1
    foreach row {2 4 6} {
        grid rowconfigure .tools.right $row -weight 1
    }
    grid columnconfigure .tools.right 0 -weight 1
    grid columnconfigure .tools.right 1 -weight 1
    bind .tools.left.names <<ListboxSelect>> ::oodzGui::selectTool
    bind .tools.right.arguments <Control-Return> {
        ::oodzGui::runSelectedTool
        break
    }
    if {[.tools.left.names size] > 0} {
        .tools.left.names selection set 0
        ::oodzGui::selectTool
    }
}

proc ::oodzGui::close {} {
    foreach name {
        agent historyStore registry pluginWorker instructionRegistry \
        skillRegistry processRunner client backend config
    } {
        variable $name
        set object [set $name]
        if {$object ne "" && [info object isa object $object]} {
            $object destroy
        }
    }
    destroy .
}

proc ::oodzGui::maximizeWindow {} {
    update idletasks
    set windowSystem [tk windowingsystem]
    set maximized [expr {$windowSystem eq "win32"
        ? ![catch {wm state . zoomed}]
        : ![catch {wm attributes . -zoomed 1}]}]
    if {!$maximized} {
        wm geometry . [format "%dx%d+0+0" [winfo screenwidth .] [winfo screenheight .]]
    }
}

proc ::oodzGui::applyConfiguredTheme {configObject} {
    variable scriptDir
    set themePackage [string trim [$configObject get GUI.theme_package ""]]
    set requested [string trim [$configObject get GUI.theme ""]]
    if {$themePackage ne ""} {
        foreach packageDir [glob -nocomplain -types d -directory [file join $scriptDir lib] *] {
            if {![file isfile [file join $packageDir pkgIndex.tcl]]} {
                continue
            }
            if {$packageDir ni $::auto_path} {
                lappend ::auto_path $packageDir
            }
        }
        if {[catch {package require $themePackage} message]} {
            error "Could not load GUI.theme_package '$themePackage': $message"
        }
    }
    if {$requested eq ""} {
        return
    }
    set available [ttk::style theme names]
    if {$requested ni $available} {
        error "GUI.theme is not installed: $requested (available: [join $available {, }])"
    }
    ttk::style theme use $requested
}

proc ::oodzGui::applyTextTheme {} {
    variable darkTheme
    if {![winfo exists .input]} {
        return
    }
    if {$darkTheme} {
        .input configure -background #404452 -foreground #d3dae3 -insertbackground white
    } else {
        .input configure -background white -foreground #5c616c -insertbackground #5c616c
    }
}

proc ::oodzGui::toggleTheme {} {
    variable darkTheme
    set theme [expr {$darkTheme ? "Arc-Dark" : "Arc"}]
    if {$theme ni [ttk::style theme names]} {
        set darkTheme [expr {!$darkTheme}]
        return
    }
    ttk::style theme use $theme
    ::oodzGui::applyTextTheme
}

proc ::oodzGui::contextAction {eventName} {
    variable contextWidget
    if {$contextWidget eq "" || ![winfo exists $contextWidget]} {
        return
    }
    focus $contextWidget
    event generate $contextWidget $eventName
}

proc ::oodzGui::contextSelectAll {} {
    variable contextWidget
    if {$contextWidget eq "" || ![winfo exists $contextWidget]} {
        return
    }
    focus $contextWidget
    $contextWidget tag add sel 1.0 end-1c
}

proc ::oodzGui::showTextContextMenu {widget rootX rootY localX localY} {
    variable contextWidget
    set contextWidget $widget
    set editable [expr {[$widget cget -state] eq "normal"}]
    set hasSelection [expr {![catch {$widget index sel.first}]}]
    set hasClipboard [expr {![catch {clipboard get -displayof $widget}]}]
    set hasText [expr {[$widget compare end-1c > 1.0]}]

    .textContext entryconfigure Copy -state [expr {$hasSelection ? "normal" : "disabled"}]
    .textContext entryconfigure Cut -state [expr {$editable && $hasSelection ? "normal" : "disabled"}]
    .textContext entryconfigure Paste -state [expr {$editable && $hasClipboard ? "normal" : "disabled"}]
    .textContext entryconfigure "Select All" -state [expr {$hasText ? "normal" : "disabled"}]
    if {$editable && !$hasSelection} {
        $widget mark set insert @$localX,$localY
    }
    tk_popup .textContext $rootX $rootY
}

proc ::oodzGui::buildWidgets {} {
    variable darkTheme
    wm title . "OODZ Agent"
    wm minsize . 700 520
    ttk::frame .main -padding 12
    text .conversation -wrap word -state disabled -padx 12 -pady 12 -background #151821 -foreground #d8dee9 -insertbackground white -selectbackground #5294e2 -selectforeground white -relief flat
    ttk::scrollbar .scroll -orient vertical -command [list .conversation yview]
    .conversation configure -yscrollcommand [list .scroll set]
    .conversation tag configure You -foreground #ff87d7
    .conversation tag configure YouLabel -foreground #ff87d7
    .conversation tag configure assistant -foreground #87d7ff
    .conversation tag configure assistantLabel -foreground #87d7ff
    .conversation tag configure Assistant -foreground #87d7ff
    .conversation tag configure AssistantLabel -foreground #87d7ff
    .conversation tag configure Error -foreground #ff6b6b
    .conversation tag configure ErrorLabel -foreground #ff6b6b
    ::oodzMarkdownTk::attach .conversation
    text .input -height 5 -wrap word -padx 8 -pady 8 -selectbackground #5294e2 -selectforeground white
    ttk::frame .actions
    ttk::button .send -text "Send" -command ::oodzGui::send
    ttk::button .new -text "New" -command ::oodzGui::newConversation
    ttk::button .skillsButton -text "Skills" -command ::oodzGui::showSkills
    ttk::button .toolsButton -text "Tools" -command ::oodzGui::showTools
    ttk::label .status -text "Ready"
    ttk::label .hint -text "Ctrl+Enter sends"
    set darkTheme [expr {[ttk::style theme use] eq "Arc-Dark"}]
    ttk::checkbutton .themeToggle -text "Dark" -variable ::oodzGui::darkTheme -command ::oodzGui::toggleTheme
    if {"Arc" ni [ttk::style theme names] || "Arc-Dark" ni [ttk::style theme names]} {
        .themeToggle configure -state disabled
    }
    menu .textContext -tearoff 0
    .textContext add command -label Cut -command [list ::oodzGui::contextAction <<Cut>>]
    .textContext add command -label Copy -command [list ::oodzGui::contextAction <<Copy>>]
    .textContext add command -label Paste -command [list ::oodzGui::contextAction <<Paste>>]
    .textContext add separator
    .textContext add command -label "Select All" -command ::oodzGui::contextSelectAll
    grid .main -row 0 -column 0 -sticky nsew
    grid .conversation -in .main -row 0 -column 0 -sticky nsew
    grid .scroll -in .main -row 0 -column 1 -sticky ns
    grid .input -in .main -row 1 -column 0 -columnspan 2 -sticky ew -pady {10 8}
    grid .actions -in .main -row 2 -column 0 -columnspan 2 -sticky ew
    pack .send .new .toolsButton .skillsButton -in .actions -side left -padx {0 8}
    pack .hint .status .themeToggle -in .actions -side right -padx {8 0}
    ::oodzGui::applyTextTheme
    grid rowconfigure . 0 -weight 1
    grid columnconfigure . 0 -weight 1
    grid rowconfigure .main 0 -weight 1
    grid columnconfigure .main 0 -weight 1
    bind .input <Control-Return> {::oodzGui::send; break}
    foreach widget {.conversation .input} {
        bind $widget <Button-3> {::oodzGui::showTextContextMenu %W %X %Y %x %y; break}
        if {[tk windowingsystem] eq "aqua"} {
            bind $widget <Control-Button-1> {::oodzGui::showTextContextMenu %W %X %Y %x %y; break}
        }
    }
    wm protocol . WM_DELETE_WINDOW ::oodzGui::close
    after idle ::oodzGui::maximizeWindow
}

proc ::oodzGui::start {} {
    variable scriptDir
    variable agent
    variable client
    variable registry
    variable skillRegistry
    variable instructionRegistry
    variable processRunner
    variable pluginWorker
    variable config
    variable backend
    variable historyStore
    
    set config [::Config new]
    set backend [::Config::Backend::Ini new]
    $config useBackend $backend [file join $scriptDir conf conf.ini]
    $config load
    ::oodzGui::applyConfiguredTheme $config
    ::oodzGui::buildWidgets
    set logPath [$config get Logging.file .oodz/oodz.log]
    if {[file pathtype $logPath] ne "absolute"} {
        set logPath [file join $scriptDir $logPath]
    }
    file mkdir [file dirname $logPath]
    ::tLogger setAppenderFactory [list ::FileAppender new $logPath]
    [::tLogger getLogger "Global"] setLogLevel [$config get Logging.level info]
    set workspaceRoot [::resolveWorkspaceRoot $scriptDir [$config get Workspace.root .]]
    set instructions [::loadWorkspaceInstructions $workspaceRoot [$config get Workspace.instructions ""] [$config get Workspace.instructions_max_file_bytes 16384]]
    set referenceRoots [dict create]
    set oodzRoot [::resolveOptionalReferenceRoot $scriptDir [$config get OODZ.root ""] OODZ.root]
    if {$oodzRoot ne ""} {
        dict set referenceRoots oodz $oodzRoot
    }
    set client [tLLMClient new $config]
    set skillRegistry [tSkillRegistry new [::resolveSkillDirectories $scriptDir [$config get Skills.directories ""]] [$config get Skills.max_file_bytes 65536]]
    set instructionRegistry [tInstructionRegistry new $workspaceRoot [$config get Workspace.instructions ""] [$config get Workspace.instructions_max_file_bytes 16384] [$config get Workspace.instructions_max_total_bytes 65536]]
    set runnerEnabled [$config get Runner.enabled false]
    if {![string is boolean -strict $runnerEnabled]} {
        error "Runner.enabled must be boolean"
    }
    set projectTestsEnabled false
    if {$runnerEnabled} {
        set processRunner [tProcessRunner new $workspaceRoot [$config get Runner.tclsh tclsh9.0] [$config get Runner.timeout_ms 10000] [$config get Runner.max_output_chars 65536] "" [dict create fossil [$config get Executables.fossil fossil]]]
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
    set pluginCore [::parsePluginNames [$config get Plugins.core "read_file,list_files,search_files,file_info,system_info,apply_patch,write_file"]]
    set pluginDirectories [::resolvePluginDirectories $scriptDir [$config get Plugins.directories ""]]
    set workerEnabled [$config get Plugins.worker_thread true]
    if {![string is boolean -strict $workerEnabled]} {
        error "Plugins.worker_thread must be boolean"
    }
    if {$workerEnabled} {
        set runnerConfig [dict create enabled $runnerEnabled tclsh [$config get Runner.tclsh tclsh9.0] timeout_ms [$config get Runner.timeout_ms 10000] max_output_chars [$config get Runner.max_output_chars 65536] \
            executable_aliases [dict create fossil [$config get Executables.fossil fossil]] project_tests_enabled $projectTestsEnabled project_tests_executable [$config get Runner.project_tests_executable tclsh9.0] \
            project_tests_arguments [$config get Runner.project_tests_arguments tests/all.tcl] project_tests_timeout_ms [$config get Runner.project_tests_timeout_ms 60000]]
        set pluginWorker [tPluginWorker new $scriptDir $workspaceRoot $pluginDirectories [$config get Plugins.timeout_ms 1000] [$config get Plugins.max_output_chars 65536] $referenceRoots $runnerConfig]
    }
    set modelInfoCallback ""
    if {"modelInfo" in [info object methods $client -all]} {
        set modelInfoCallback [list $client modelInfo]
    }
    set registry [tPluginRegistry new $workspaceRoot $pluginDirectories ::oodzGui::approve [$config get Plugins.timeout_ms 1000] \
        [$config get Plugins.max_output_chars 65536] $referenceRoots $skillRegistry $instructionRegistry $processRunner $pluginLazyLoading $pluginCore "" $pluginWorker $modelInfoCallback]
    set systemRole [::buildAgentSystemRole $config $instructions [$skillRegistry summaries] [$instructionRegistry enabled] $runnerEnabled $pluginLazyLoading]
    set systemRole [::addModelIdentityToSystemRole $systemRole $client]
    set agent [tAgent new [$config get Agent.name] $systemRole $client $registry [$config get Agent.max_iterations 16] ::oodzGui::streamChunk [$config get Agent.max_history_messages 40] [$config get Agent.summarize_history false]]
    set historyPath [$config get Agent.history_file .oodz/history.json]
    if {[file pathtype $historyPath] ne "absolute"} {
        set historyPath [file join $scriptDir $historyPath]
    }
    set historyStore [tConversationStore new $historyPath]
    $agent replaceHistoryState [$historyStore loadState]
    ::oodzGui::renderHistory
    focus .input
}

if {[info exists ::argv0] && [file normalize [info script]] eq [file normalize $::argv0]} {
    if {[catch {::oodzGui::start} message]} {
        puts stderr "GUI error: $message"
        exit 1
    }
}
