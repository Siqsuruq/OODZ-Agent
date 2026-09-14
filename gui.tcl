#!/usr/bin/env wish


namespace eval ::oodzGui {
    variable scriptDir [file dirname [file normalize [info script]]]
    variable agent ""
    variable client ""
    variable registry ""
    variable skillRegistry ""
    variable instructionRegistry ""
    variable processRunner ""
    variable commandRunner ""
    variable commandExecutor ""
    variable pluginWorker ""
    variable config ""
    variable backend ""
    variable historyStore ""
    variable changeTracker ""
    variable diagnostics ""
    variable diagnosticsRefreshAfter ""
    variable diagnosticsRefreshInterval 10000
    variable logPath ""
    variable logRefreshAfter ""
    variable logRefreshInterval 5000
    variable logLevelFilter All
    variable workspaceRoot ""
    variable instructionPath ""
    variable approveAll 0
    variable approvalResult 0
    variable busy 0
    variable toolDefinitions [dict create]
    variable toolFields {}
    variable toolFieldValues
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
    if {$approveAll && $name ni {run_tcl_file run_project_tests exec_command}} {
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
    if {$name eq "exec_command"} {
        set message "Execute external command?\n\nExecutable:\n[dict get $arguments resolved_executable]\n\nArguments:\n[dict get $arguments arguments]\n\nWorking directory:\n[dict get $arguments resolved_working_directory]\n\nTimeout: [dict get $arguments timeout_ms] ms\n\nWARNING: No OS sandbox is active."
    } elseif {$name in {run_tcl_file run_project_tests}} {
        set action [expr {$name eq "run_tcl_file"
            ? "Tcl file$target"
            : "configured project tests"}]
        set message "Execute $action?\n\nWARNING: No OS sandbox may be active. The code can use your account permissions."
    } else {
        set message "Allow write plugin '$name'?$target"
    }
    ttk::label .approval.message -text $message -justify left
    ttk::button .approval.yes -text "Yes" -command [list ::oodzGui::approvalChoice 1]
    if {$name ni {run_tcl_file run_project_tests exec_command}} {
        ttk::button .approval.all -text "All for session" -command [list ::oodzGui::approvalChoice 2]
    }
    ttk::button .approval.no -text "Deny" -command [list ::oodzGui::approvalChoice 0]
    grid .approval.message -row 0 -column 0 -columnspan 3 -sticky nsew -padx 16 -pady {16 20}
    grid .approval.yes -row 1 -column 0 -padx {16 4} -pady {0 16} -sticky ew
    if {$name ni {run_tcl_file run_project_tests exec_command}} {
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
    variable changeTracker
    variable registry
    if {$busy} {
        return
    }
    set task [string trim [.input get 1.0 end-1c]]
    if {$task eq ""} {
        return
    }
    set displayedTask $task
    if {[regexp {^/oodz_trns(?:[[:space:]]+(.*))?$} \
            $task -> translationLabel]} {
        if {![info exists translationLabel]
                || [string trim $translationLabel] eq ""} {
            .input delete 1.0 end
            ::oodzGui::appendMessage Error "Usage: /oodz_trns label"
            focus .input
            return
        }
        if {[catch {$registry activate save_translation} activationError]} {
            .input delete 1.0 end
            ::oodzGui::appendMessage Error \
                "Cannot start translation: $activationError"
            focus .input
            return
        }
        set task [::buildTranslationTask $translationLabel]
    }
    if {[regexp {^/tool(?:[[:space:]]|$)} $task]} {
        .input delete 1.0 end
        ::oodzGui::appendMessage You $task
        if {[catch {
            lassign [::parseDirectToolCommand $task] toolName toolArguments
            $registry invoke $toolName $toolArguments
        } result]} {
            ::oodzGui::appendMessage Error "Tool error: $result"
        } else {
            ::oodzGui::appendMessage Tool $result
        }
        .status configure -text "Ready"
        focus .input
        return
    }
    set busy 1
    .input delete 1.0 end
    .send configure -state disabled
    .stop configure -state normal
    .status configure -text "Working…"
    ::oodzGui::appendMessage You $displayedTask
    .conversation configure -state normal
    .conversation insert end "Assistant\n" assistantLabel
    .conversation configure -state disabled
    ::oodzMarkdownTk::begin .conversation assistant
    update idletasks
    set changeSnapshot ""
    if {$changeTracker ne ""} {
        set changeSnapshot [$changeTracker snapshot]
    }
    if {[catch {$agent run $task} result options]} {
        ::oodzMarkdownTk::finish .conversation
        if {[dict exists $options -errorcode]
                && [dict get $options -errorcode] eq {OODZ CANCELLED}} {
            ::oodzGui::appendMessage Status "Request stopped."
        } else {
            ::oodzGui::appendMessage Error "Error: $result"
        }
    } else {
        ::oodzMarkdownTk::finish .conversation
        .conversation configure -state normal
        .conversation insert end "\n"
        .conversation configure -state disabled
        .conversation see end
    }
    if {$changeTracker ne ""} {
        set changes [$changeTracker compare \
            $changeSnapshot [$changeTracker snapshot]]
        set report [$changeTracker format $changes]
        if {$report ne ""} {
            ::oodzGui::appendMessage Changes $report
        }
    }
    if {[catch {::oodzGui::saveHistory} historyError]} {
        ::oodzGui::appendMessage Error "History error: $historyError"
    }
    set busy 0
    .send configure -state normal
    .stop configure -state disabled
    .status configure -text "Ready"
    focus .input
}

proc ::oodzGui::stop {} {
    variable agent
    variable busy
    if {!$busy} {
        return
    }
    .stop configure -state disabled
    .status configure -text "Stopping…"
    $agent cancel
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

proc ::oodzGui::refreshSystemRole {} {
    variable agent
    variable client
    variable config
    variable instructionRegistry
    variable processRunner
    variable skillRegistry
    variable workspaceRoot

    set instructions [::loadWorkspaceInstructions $workspaceRoot \
        [$config get Workspace.instructions ""] \
        [$config get Workspace.instructions_max_file_bytes 16384]]
    set pluginLazyLoading [$config get Plugins.lazy_loading true]
    set role [::buildAgentSystemRole $config $instructions \
        [$skillRegistry summaries] [$instructionRegistry enabled] \
        [expr {$processRunner ne ""}] $pluginLazyLoading]
    $agent configureSystemRole \
        [::addModelIdentityToSystemRole $role $client]
}

proc ::oodzGui::saveWorkspaceInstructions {} {
    variable config
    variable instructionPath

    set content [.instructions.editor get 1.0 end-1c]
    set bytes [encoding convertto utf-8 $content]
    set maximum [$config get Workspace.instructions_max_file_bytes 16384]
    if {[string length $bytes] > $maximum} {
        tk_messageBox -parent .instructions -icon error -type ok \
            -title "Instructions too large" \
            -message "Workspace instructions exceed the $maximum-byte limit."
        return
    }
    if {[catch {
        set channel [open $instructionPath wb]
        try {
            puts -nonewline $channel $bytes
        } finally {
            ::close $channel
        }
        ::oodzGui::refreshSystemRole
    } message]} {
        tk_messageBox -parent .instructions -icon error -type ok \
            -title "Could not save instructions" -message $message
        return
    }
    .instructions.status configure -text "Saved. Active for the next request."
}

proc ::oodzGui::editWorkspaceInstructions {} {
    variable config
    variable instructionPath
    variable workspaceRoot

    set configuredPath [string trim [$config get Workspace.instructions ""]]
    if {$configuredPath eq ""} {
        tk_messageBox -parent . -icon info -type ok \
            -title "Workspace instructions disabled" \
            -message "Set Workspace.instructions in conf.ini before using the editor."
        return
    }
    if {[file pathtype $configuredPath] ne "relative"} {
        tk_messageBox -parent . -icon error -type ok \
            -title "Invalid instruction path" \
            -message "Workspace.instructions must be relative to the workspace."
        return
    }
    set instructionPath [file normalize [file join $workspaceRoot $configuredPath]]
    if {![::PluginSupport::isWithin $instructionPath $workspaceRoot]} {
        tk_messageBox -parent . -icon error -type ok \
            -title "Invalid instruction path" \
            -message "The instruction file must remain inside the workspace."
        return
    }
    set content ""
    if {[file isfile $instructionPath]} {
        if {[catch {
            set content [::loadWorkspaceInstructions $workspaceRoot \
                $configuredPath \
                [$config get Workspace.instructions_max_file_bytes 16384]]
        } message]} {
            tk_messageBox -parent . -icon error -type ok \
                -title "Could not read instructions" -message $message
            return
        }
    }

    catch {destroy .instructions}
    toplevel .instructions
    wm title .instructions "Workspace Instructions"
    wm transient .instructions .
    wm minsize .instructions 640 440
    ttk::label .instructions.path -text $instructionPath -anchor w
    text .instructions.editor -wrap word -undo true -padx 10 -pady 10
    ttk::scrollbar .instructions.scroll -orient vertical \
        -command [list .instructions.editor yview]
    .instructions.editor configure \
        -yscrollcommand [list .instructions.scroll set]
    .instructions.editor insert 1.0 $content
    ttk::label .instructions.status \
        -text "These instructions are added to every model request."
    ttk::frame .instructions.actions
    ttk::button .instructions.actions.save -text "Save" \
        -command ::oodzGui::saveWorkspaceInstructions
    ttk::button .instructions.actions.close -text "Close" \
        -command [list destroy .instructions]
    grid .instructions.path -row 0 -column 0 -columnspan 2 \
        -sticky ew -padx 12 -pady {12 8}
    grid .instructions.editor -row 1 -column 0 -sticky nsew -padx {12 0}
    grid .instructions.scroll -row 1 -column 1 -sticky ns -padx {0 12}
    grid .instructions.status -row 2 -column 0 -columnspan 2 \
        -sticky w -padx 12 -pady 8
    grid .instructions.actions -row 3 -column 0 -columnspan 2 \
        -sticky ew -padx 12 -pady {0 12}
    pack .instructions.actions.save -side left
    pack .instructions.actions.close -side right
    grid rowconfigure .instructions 1 -weight 1
    grid columnconfigure .instructions 0 -weight 1
    bind .instructions.editor <Control-s> {
        ::oodzGui::saveWorkspaceInstructions
        break
    }
    focus .instructions.editor
}

proc ::oodzGui::showAbout {} {
    tk_messageBox -parent . -icon info -type ok -title "About OODZ Agent" \
        -message "OODZ Agent $::version" \
        -detail "A professional, extensible software engineering agent built with Tcl 9."
}

proc ::oodzGui::selectTool {} {
    variable toolDefinitions
    set selection [.tools.left.names selection]
    if {[llength $selection] != 1} {
        return
    }
    set item [lindex $selection 0]
    set name [.tools.left.names set $item name]
    if {$name eq ""} {
        .tools.right.run configure -state disabled
        return
    }
    set definition [dict get $toolDefinitions $name]
    .tools.right.description configure -text [dict get $definition description]
    .tools.right.run configure -text [expr {$name eq "save_translation"
        ? "Translate and save" : "Run tool"}]
    ::oodzGui::buildToolForm $definition
    .tools.right.result configure -state normal
    .tools.right.result delete 1.0 end
    .tools.right.result configure -state disabled
    .tools.right.run configure -state normal
}

proc ::oodzGui::buildToolForm {definition} {
    variable toolFields
    variable toolFieldValues
    set toolFields {}
    array unset toolFieldValues
    foreach child [winfo children .tools.right.form] {
        destroy $child
    }

    set schema [dict get $definition parameters]
    set properties [dict getdef $schema properties {}]
    set required [dict getdef $schema required {}]
    if {[dict get $definition name] eq "save_translation"} {
        # The human supplies only the source label. The model generates the
        # strict multilingual payload required by the underlying plugin.
        set properties [dict create original [dict get $properties original]]
        set required [list original]
    }
    if {[dict size $properties] == 0} {
        ttk::label .tools.right.form.none -text "This tool has no arguments."
        grid .tools.right.form.none -row 0 -column 0 -sticky w -pady 6
        return
    }

    set row 0
    dict for {name property} $properties {
        set type [dict getdef $property type string]
        set isRequired [expr {$name in $required}]
        set label [expr {$isRequired ? "$name *" : $name}]
        ttk::label .tools.right.form.label$row -text $label -anchor nw
        set variableName ::oodzGui::toolFieldValues($row)
        set toolFieldValues($row) [dict getdef $property default ""]
        set mode variable

        if {[dict exists $property enum]} {
            ttk::combobox .tools.right.form.value$row -state readonly \
                -textvariable $variableName \
                -values [linsert [dict get $property enum] 0 ""]
        } elseif {$type eq "boolean"} {
            set toolFieldValues($row) [expr {
                [dict exists $property default]
                && [dict get $property default] ? 1 : 0}]
            ttk::checkbutton .tools.right.form.value$row \
                -variable $variableName
        } elseif {$type eq "string"
                && $name in {content patch old_text new_text json note}} {
            set mode text
            text .tools.right.form.value$row -height 3 -wrap word \
                -padx 6 -pady 4
            if {$toolFieldValues($row) ne ""} {
                .tools.right.form.value$row insert 1.0 $toolFieldValues($row)
            }
        } else {
            ttk::entry .tools.right.form.value$row \
                -textvariable $variableName
        }
        set description [dict getdef $property description ""]
        if {$type in {object array}} {
            append description [expr {
                $description eq "" ? "JSON value." : " (JSON value)"}]
        }
        ttk::label .tools.right.form.help$row -text $description \
            -anchor nw -justify left -wraplength 440
        grid .tools.right.form.label$row -row $row -column 0 \
            -sticky nw -padx {0 8} -pady 4
        grid .tools.right.form.value$row -row $row -column 1 \
            -sticky ew -pady 4
        grid .tools.right.form.help$row -row [incr row] -column 1 \
            -sticky ew -pady {0 5}
        lappend toolFields [dict create name $name type $type \
            required $isRequired mode $mode index [expr {$row - 1}]]
        incr row
    }
    grid columnconfigure .tools.right.form 1 -weight 1
}

proc ::oodzGui::toolFormArguments {} {
    variable toolFields
    variable toolFieldValues
    set fields {}
    foreach field $toolFields {
        set index [dict get $field index]
        if {[dict get $field mode] eq "text"} {
            set value [.tools.right.form.value$index get 1.0 end-1c]
        } else {
            set value $toolFieldValues($index)
        }
        set type [dict get $field type]
        set name [dict get $field name]
        if {$type ne "boolean" && $value eq ""} {
            if {[dict get $field required]} {
                error "Required argument is empty: $name"
            }
            continue
        }
        switch -- $type {
            integer {
                if {![string is entier -strict $value]} {
                    error "$name must be an integer"
                }
                set encoded $value
            }
            number {
                if {![string is double -strict $value]} {
                    error "$name must be a number"
                }
                set encoded $value
            }
            boolean {
                set encoded [expr {$value ? "true" : "false"}]
            }
            object - array {
                set trimmed [string trim $value]
                set expected [expr {$type eq "object" ? "\{" : "\["}]
                if {$trimmed eq "" || [string index $trimmed 0] ne $expected
                        || [catch {::json::json2dict $trimmed}]} {
                    error "$name must contain a valid JSON $type"
                }
                set encoded $trimmed
            }
            default {
                set encoded [::json::write string $value]
            }
        }
        lappend fields $name $encoded
    }
    ::json::write object {*}$fields
}

proc ::oodzGui::runSelectedTool {} {
    variable registry
    variable busy
    set selection [.tools.left.names selection]
    if {$busy || [llength $selection] != 1} {
        return
    }
    set name [.tools.left.names set [lindex $selection 0] name]
    if {$name eq ""} {
        return
    }
    if {[catch {::oodzGui::toolFormArguments} arguments]} {
        .tools.right.result configure -state normal
        .tools.right.result delete 1.0 end
        .tools.right.result insert end "Error: $arguments" error
        .tools.right.result configure -state disabled
        return
    }
    if {$name eq "save_translation"} {
        set values [::json::json2dict $arguments]
        set label [dict get $values original]
        destroy .tools
        .input delete 1.0 end
        .input insert 1.0 "/oodz_trns $label"
        ::oodzGui::send
        return
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
    # A human browsing the Tools window should see every installed plugin;
    # lazy loading limits model context, not the GUI catalog.
    foreach definition [$registry definitions true] {
        dict set toolDefinitions [dict get $definition name] $definition
    }

    toplevel .tools
    wm title .tools "Run a tool"
    wm transient .tools .
    wm minsize .tools 760 520

    ttk::frame .tools.left -padding 8
    ttk::frame .tools.right -padding 8
    ttk::treeview .tools.left.names -show tree -selectmode browse \
        -columns [list name] -displaycolumns {} -height 20
    ttk::scrollbar .tools.left.namesScroll -orient vertical -command [list .tools.left.names yview]
    .tools.left.names configure -yscrollcommand [list .tools.left.namesScroll set]
    ttk::label .tools.right.description -text "Select a tool" -anchor nw -justify left -wraplength 500
    ttk::label .tools.right.argumentsLabel -text "Arguments (* required)"
    ttk::frame .tools.right.form
    ttk::label .tools.right.resultLabel -text "Result"
    text .tools.right.result -height 10 -wrap word -state disabled -padx 8 -pady 8
    ttk::scrollbar .tools.right.resultScroll -orient vertical \
        -command [list .tools.right.result yview]
    .tools.right.result configure \
        -yscrollcommand [list .tools.right.resultScroll set]
    .tools.right.result tag configure error -foreground #c62828
    ttk::button .tools.right.run -text "Run tool" -state disabled -command ::oodzGui::runSelectedTool
    ttk::button .tools.right.close -text "Close" -command [list destroy .tools]

    set categoryTitles [dict create \
        database "Database" filesystem "Filesystem" vcs "Version Control" \
        web "Web" utility "Utilities" system "System" \
        execution "Execution" skills "Skills" other "Other"]
    set categories [dict create]
    dict for {name definition} $toolDefinitions {
        set category [dict getdef $definition category other]
        dict lappend categories $category $name
    }
    foreach category [lsort [dict keys $categories]] {
        set title [dict getdef $categoryTitles $category \
            [string totitle [string map {_ " " - " "} $category]]]
        set parent [.tools.left.names insert {} end \
            -id "category:$category" -text $title -open false]
        foreach name [lsort [dict get $categories $category]] {
            .tools.left.names insert $parent end -id "tool:$name" \
                -text $name -values [list $name]
        }
    }
    grid .tools.left -row 0 -column 0 -sticky nsew
    grid .tools.right -row 0 -column 1 -sticky nsew
    grid .tools.left.names -row 0 -column 0 -sticky nsew
    grid .tools.left.namesScroll -row 0 -column 1 -sticky ns
    grid .tools.right.description -row 0 -column 0 -columnspan 3 -sticky ew -pady {0 10}
    grid .tools.right.argumentsLabel -row 1 -column 0 -columnspan 3 -sticky w
    grid .tools.right.form -row 2 -column 0 -columnspan 3 -sticky nsew -pady {4 10}
    grid .tools.right.resultLabel -row 3 -column 0 -columnspan 3 -sticky w
    grid .tools.right.result -row 4 -column 0 -columnspan 2 -sticky nsew -pady {4 10}
    grid .tools.right.resultScroll -row 4 -column 2 -sticky ns -pady {4 10}
    grid .tools.right.run -row 5 -column 0 -sticky w
    grid .tools.right.close -row 5 -column 1 -sticky e
    grid rowconfigure .tools 0 -weight 1
    grid columnconfigure .tools 1 -weight 1
    grid rowconfigure .tools.left 0 -weight 1
    grid columnconfigure .tools.left 0 -weight 1
    foreach row {2 4} {
        grid rowconfigure .tools.right $row -weight 1
    }
    grid columnconfigure .tools.right 0 -weight 1
    grid columnconfigure .tools.right 1 -weight 1
    grid columnconfigure .tools.right 2 -weight 0
    bind .tools.left.names <<TreeviewSelect>> ::oodzGui::selectTool
}

proc ::oodzGui::close {} {
    ::oodzGui::stopDiagnosticsRefresh
    ::oodzGui::stopLogRefresh
    foreach name {
        agent historyStore changeTracker diagnostics registry pluginWorker commandExecutor commandRunner \
        instructionRegistry skillRegistry processRunner client backend config
    } {
        variable $name
        set object [set $name]
        if {$object ne "" && [info object isa object $object]} {
            $object destroy
        }
    }
    destroy .
}

proc ::oodzGui::diagnosticNumber {value} {
    if {$value >= 1000000} {return [format "%.2fM" [expr {$value / 1000000.0}]]}
    if {$value >= 1000} {return [format "%.1fK" [expr {$value / 1000.0}]]}
    return $value
}

proc ::oodzGui::drawDiagnosticBars {canvas counts} {
    $canvas delete all
    set width [winfo width $canvas]
    if {$width < 100} {set width 760}
    set rows {}
    dict for {name count} $counts {lappend rows [list $count $name]}
    set rows [lrange [lsort -integer -decreasing -index 0 $rows] 0 9]
    if {[llength $rows] == 0} {
        $canvas create text 12 20 -anchor nw -text "No tool calls recorded yet."
        return
    }
    set maximum [lindex [lindex $rows 0] 0]
    set y 12
    foreach row $rows {
        lassign $row count name
        set barWidth [expr {int(($width - 220) * $count / double($maximum))}]
        $canvas create text 8 [expr {$y + 9}] -anchor w -text $name
        $canvas create rectangle 150 $y [expr {150 + $barWidth}] \
            [expr {$y + 18}] -fill #5294e2 -outline {}
        $canvas create text [expr {160 + $barWidth}] [expr {$y + 9}] \
            -anchor w -text $count
        incr y 23
    }
}

proc ::oodzGui::drawDiagnosticTimeline {canvas events} {
    $canvas delete all
    set values {}
    foreach event $events {
        if {[dict get $event type] eq "llm_request"
                && [dict exists $event context_chars]} {
            lappend values [dict get $event context_chars]
        }
    }
    set values [lrange $values end-59 end]
    set width [winfo width $canvas]
    set height [winfo height $canvas]
    if {$width < 100} {set width 760}
    if {$height < 100} {set height 210}
    $canvas create text 8 8 -anchor nw -text "Context characters per LLM request (latest 60)"
    if {[llength $values] == 0} {
        $canvas create text 8 35 -anchor nw -text "No requests recorded yet."
        return
    }
    set maximum [lindex [lsort -integer -decreasing $values] 0]
    if {$maximum < 1} {set maximum 1}
    set left 45
    set top 30
    set bottom [expr {$height - 22}]
    set plotWidth [expr {$width - $left - 15}]
    set plotHeight [expr {$bottom - $top}]
    $canvas create line $left $top $left $bottom [expr {$left + $plotWidth}] $bottom -fill #888888
    $canvas create text 4 $top -anchor nw -text [::oodzGui::diagnosticNumber $maximum]
    set points {}
    set divisor [expr {max(1, [llength $values] - 1)}]
    set index 0
    foreach value $values {
        set x [expr {$left + $plotWidth * $index / double($divisor)}]
        set y [expr {$bottom - $plotHeight * $value / double($maximum)}]
        lappend points $x $y
        incr index
    }
    if {[llength $values] == 1} {
        $canvas create oval [expr {[lindex $points 0]-2}] [expr {[lindex $points 1]-2}] \
            [expr {[lindex $points 0]+2}] [expr {[lindex $points 1]+2}] -fill #a9dc52
    } else {
        $canvas create line {*}$points -fill #a9dc52 -width 2
    }
}

proc ::oodzGui::refreshDiagnostics {} {
    variable diagnostics
    if {$diagnostics eq "" || ![winfo exists .diagnostics]} {return}
    set summary [$diagnostics summary]
    set requestCount [dict get $summary requests]
    set duration [dict get $summary request_duration_ms]
    set average [expr {$requestCount > 0 ? round($duration / double($requestCount)) : 0}]
    set hasUsage 0
    foreach event [$diagnostics events] {
        if {[dict get $event type] eq "usage"} {set hasUsage 1; break}
    }
    set values [dict create \
        requests $requestCount \
        tokens [expr {$hasUsage ? [::oodzGui::diagnosticNumber [dict get $summary total_tokens]] : "N/A"}] \
        tools [dict get $summary tool_calls] \
        failures [expr {[dict get $summary tool_failures] + [dict get $summary request_failures]}] \
        skipped [dict get $summary skipped_calls] \
        average "${average} ms" \
        latest_tps [expr {[dict get $summary measured_responses] > 0 \
            ? "[format %.1f [dict get $summary latest_tokens_per_second]] tok/s" : "N/A"}] \
        overall_tps [expr {[dict get $summary measured_responses] > 0 \
            ? "[format %.1f [dict get $summary average_tokens_per_second]] tok/s" : "N/A"}]]
    dict for {name value} $values {
        .diagnostics.cards.value_$name configure -text $value
    }
    ::oodzGui::drawDiagnosticBars .diagnostics.toolChart [dict get $summary tools]
    ::oodzGui::drawDiagnosticTimeline .diagnostics.contextChart [$diagnostics events]
}

proc ::oodzGui::stopDiagnosticsRefresh {} {
    variable diagnosticsRefreshAfter
    if {$diagnosticsRefreshAfter ne ""} {
        after cancel $diagnosticsRefreshAfter
        set diagnosticsRefreshAfter ""
    }
}

proc ::oodzGui::scheduleDiagnosticsRefresh {} {
    variable diagnosticsRefreshAfter
    variable diagnosticsRefreshInterval
    ::oodzGui::stopDiagnosticsRefresh
    if {[winfo exists .diagnostics]} {
        set diagnosticsRefreshAfter [after $diagnosticsRefreshInterval \
            ::oodzGui::automaticDiagnosticsRefresh]
    }
}

proc ::oodzGui::automaticDiagnosticsRefresh {} {
    variable diagnosticsRefreshAfter
    set diagnosticsRefreshAfter ""
    if {![winfo exists .diagnostics]} {return}
    ::oodzGui::refreshDiagnostics
    ::oodzGui::scheduleDiagnosticsRefresh
}

proc ::oodzGui::closeDiagnostics {} {
    ::oodzGui::stopDiagnosticsRefresh
    catch {destroy .diagnostics}
}

proc ::oodzGui::clearDiagnostics {} {
    variable diagnostics
    $diagnostics clear
    ::oodzGui::refreshDiagnostics
}

proc ::oodzGui::showDiagnostics {} {
    variable diagnosticsRefreshInterval
    ::oodzGui::closeDiagnostics
    toplevel .diagnostics
    wm title .diagnostics "OODZ Diagnostics"
    wm minsize .diagnostics 760 600
    ttk::frame .diagnostics.cards -padding 10
    set index 0
    foreach {name label} {
        requests Requests tokens Tokens tools {Tool calls}
        failures Failures skipped Skipped average {Avg response}
        latest_tps {Latest tok/s} overall_tps {Overall tok/s}
    } {
        ttk::labelframe .diagnostics.cards.card_$name -text $label -padding 10
        ttk::label .diagnostics.cards.value_$name -text 0 -font TkHeadingFont
        pack .diagnostics.cards.value_$name -in .diagnostics.cards.card_$name
        set row [expr {$index / 4}]
        set column [expr {$index % 4}]
        grid .diagnostics.cards.card_$name -row $row \
            -column $column -sticky nsew -padx 4 -pady 4
        grid columnconfigure .diagnostics.cards $column -weight 1
        incr index
    }
    canvas .diagnostics.toolChart -height 245 -highlightthickness 1 \
        -highlightbackground #777777
    canvas .diagnostics.contextChart -height 220 -highlightthickness 1 \
        -highlightbackground #777777
    ttk::frame .diagnostics.actions -padding 10
    ttk::button .diagnostics.refresh -text Refresh \
        -command ::oodzGui::refreshDiagnostics
    ttk::button .diagnostics.clear -text "Clear data" \
        -command ::oodzGui::clearDiagnostics
    ttk::button .diagnostics.close -text Close \
        -command ::oodzGui::closeDiagnostics
    ttk::label .diagnostics.autoRefresh -text \
        "Auto-refresh: [format %.1f [expr {$diagnosticsRefreshInterval / 1000.0}]] s"
    pack .diagnostics.refresh .diagnostics.clear -in .diagnostics.actions \
        -side left -padx {0 8}
    pack .diagnostics.autoRefresh -in .diagnostics.actions -side left
    pack .diagnostics.close -in .diagnostics.actions -side right
    grid .diagnostics.cards -row 0 -column 0 -sticky ew
    grid .diagnostics.toolChart -row 1 -column 0 -sticky nsew -padx 10 -pady 5
    grid .diagnostics.contextChart -row 2 -column 0 -sticky nsew -padx 10 -pady 5
    grid .diagnostics.actions -row 3 -column 0 -sticky ew
    grid rowconfigure .diagnostics 1 -weight 1
    grid rowconfigure .diagnostics 2 -weight 1
    grid columnconfigure .diagnostics 0 -weight 1
    bind .diagnostics.toolChart <Configure> {after idle ::oodzGui::refreshDiagnostics}
    bind .diagnostics.contextChart <Configure> {after idle ::oodzGui::refreshDiagnostics}
    wm protocol .diagnostics WM_DELETE_WINDOW ::oodzGui::closeDiagnostics
    after idle ::oodzGui::refreshDiagnostics
    ::oodzGui::scheduleDiagnosticsRefresh
}

proc ::oodzGui::recentLogLines {path {maximumLines 2000} {maximumBytes 524288}} {
    if {![file isfile $path]} {return {}}
    return [split [::readRecentLog $path $maximumLines $maximumBytes] "\n"]
}

proc ::oodzGui::refreshLogs {} {
    variable logPath
    variable logLevelFilter
    if {![winfo exists .logs]} {return}
    set lines {}
    foreach line [::oodzGui::recentLogLines $logPath] {
        if {$logLevelFilter ne "All"
                && [string first "\[$logLevelFilter\]" $line] < 0} {
            continue
        }
        lappend lines $line
    }
    set lines [lrange $lines end-499 end]
    .logs.body.text configure -state normal
    .logs.body.text delete 1.0 end
    foreach line $lines {
        set tag INFO
        foreach level {CRITICAL ERROR WARN INFO} {
            if {[string first "\[$level\]" $line] >= 0} {
                set tag $level
                break
            }
        }
        .logs.body.text insert end "$line\n" $tag
    }
    if {[llength $lines] == 0} {
        .logs.body.text insert end "No matching log entries.\n" INFO
    }
    .logs.body.text configure -state disabled
    .logs.body.text see end
}

proc ::oodzGui::stopLogRefresh {} {
    variable logRefreshAfter
    if {$logRefreshAfter ne ""} {
        after cancel $logRefreshAfter
        set logRefreshAfter ""
    }
}

proc ::oodzGui::scheduleLogRefresh {} {
    variable logRefreshAfter
    variable logRefreshInterval
    ::oodzGui::stopLogRefresh
    if {[winfo exists .logs]} {
        set logRefreshAfter [after $logRefreshInterval \
            ::oodzGui::automaticLogRefresh]
    }
}

proc ::oodzGui::automaticLogRefresh {} {
    variable logRefreshAfter
    set logRefreshAfter ""
    if {![winfo exists .logs]} {return}
    ::oodzGui::refreshLogs
    ::oodzGui::scheduleLogRefresh
}

proc ::oodzGui::closeLogs {} {
    ::oodzGui::stopLogRefresh
    catch {destroy .logs}
}

proc ::oodzGui::showLogs {} {
    variable logPath
    variable logRefreshInterval
    variable logLevelFilter
    ::oodzGui::closeLogs
    set logLevelFilter All
    toplevel .logs
    wm title .logs "OODZ Logs"
    wm minsize .logs 820 520
    ttk::frame .logs.controls -padding 10
    ttk::label .logs.controls.filterLabel -text "Severity:"
    ttk::combobox .logs.controls.filter -state readonly -width 12 \
        -values {All INFO WARN ERROR CRITICAL} \
        -textvariable ::oodzGui::logLevelFilter
    ttk::button .logs.controls.refresh -text Refresh \
        -command ::oodzGui::refreshLogs
    ttk::label .logs.controls.interval -text \
        "Auto-refresh: [format %.1f [expr {$logRefreshInterval / 1000.0}]] s"
    ttk::button .logs.controls.close -text Close \
        -command ::oodzGui::closeLogs
    pack .logs.controls.filterLabel .logs.controls.filter \
        .logs.controls.refresh .logs.controls.interval -side left -padx {0 8}
    pack .logs.controls.close -side right

    ttk::frame .logs.body -padding {10 0 10 10}
    text .logs.body.text -wrap none -state disabled -font TkFixedFont \
        -background #151821 -foreground #d8dee9 -insertbackground white
    ttk::scrollbar .logs.body.vertical -orient vertical \
        -command [list .logs.body.text yview]
    ttk::scrollbar .logs.body.horizontal -orient horizontal \
        -command [list .logs.body.text xview]
    .logs.body.text configure \
        -yscrollcommand [list .logs.body.vertical set] \
        -xscrollcommand [list .logs.body.horizontal set]
    .logs.body.text tag configure INFO -foreground #d8dee9
    .logs.body.text tag configure WARN -foreground #f4bf75
    .logs.body.text tag configure ERROR -foreground #ff6b6b
    .logs.body.text tag configure CRITICAL -foreground #ff3b3b
    grid .logs.body.text -row 0 -column 0 -sticky nsew
    grid .logs.body.vertical -row 0 -column 1 -sticky ns
    grid .logs.body.horizontal -row 1 -column 0 -sticky ew
    grid rowconfigure .logs.body 0 -weight 1
    grid columnconfigure .logs.body 0 -weight 1
    grid .logs.controls -row 0 -column 0 -sticky ew
    grid .logs.body -row 1 -column 0 -sticky nsew
    grid rowconfigure .logs 1 -weight 1
    grid columnconfigure .logs 0 -weight 1
    bind .logs.controls.filter <<ComboboxSelected>> ::oodzGui::refreshLogs
    bind .logs.body.text <Button-3> \
        {::oodzGui::showTextContextMenu %W %X %Y %x %y; break}
    wm protocol .logs WM_DELETE_WINDOW ::oodzGui::closeLogs
    ::oodzGui::refreshLogs
    ::oodzGui::scheduleLogRefresh
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
    menu .menuBar
    . configure -menu .menuBar
    menu .menuBar.file -tearoff 0
    .menuBar add cascade -label File -menu .menuBar.file
    .menuBar.file add command -label "Edit Workspace Instructions…" \
        -command ::oodzGui::editWorkspaceInstructions
    .menuBar.file add separator
    .menuBar.file add command -label Exit -command ::oodzGui::close
    menu .menuBar.view -tearoff 0
    .menuBar add cascade -label View -menu .menuBar.view
    .menuBar.view add command -label Tools -command ::oodzGui::showTools
    .menuBar.view add command -label Skills -command ::oodzGui::showSkills
    .menuBar.view add command -label Diagnostics \
        -command ::oodzGui::showDiagnostics
    .menuBar.view add command -label Logs -command ::oodzGui::showLogs
    menu .menuBar.help -tearoff 0
    .menuBar add cascade -label Help -menu .menuBar.help
    .menuBar.help add command -label "Available Skills" \
        -command ::oodzGui::showSkills
    .menuBar.help add separator
    .menuBar.help add command -label "About OODZ Agent" \
        -command ::oodzGui::showAbout
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
    .conversation tag configure Changes -foreground #a9dc52
    .conversation tag configure ChangesLabel -foreground #a9dc52
    .conversation tag configure Status -foreground #ffd75f
    .conversation tag configure StatusLabel -foreground #ffd75f
    .conversation tag configure Tool -foreground #a9dc52
    .conversation tag configure ToolLabel -foreground #a9dc52
    ::oodzMarkdownTk::attach .conversation
    text .input -height 5 -wrap word -padx 8 -pady 8 -selectbackground #5294e2 -selectforeground white
    ttk::frame .actions
    ttk::button .send -text "Send" -command ::oodzGui::send
    ttk::button .stop -text "Stop" -state disabled -command ::oodzGui::stop
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
    pack .send .stop .new .toolsButton .skillsButton -in .actions -side left -padx {0 8}
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
    variable commandRunner
    variable commandExecutor
    variable pluginWorker
    variable config
    variable backend
    variable historyStore
    variable changeTracker
    variable diagnostics
    variable diagnosticsRefreshInterval
    variable logPath
    variable logRefreshInterval
    variable workspaceRoot

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
    set logRefreshInterval [$config get Logging.refresh_interval_ms 5000]
    if {![string is integer -strict $logRefreshInterval]
            || $logRefreshInterval < 1000} {
        error "Logging.refresh_interval_ms must be an integer of at least 1000"
    }
    set workspaceRoot [::resolveWorkspaceRoot $scriptDir [$config get Workspace.root .]]
    set diagnosticsPath [$config get Diagnostics.file .oodz/diagnostics.jsonl]
    if {[file pathtype $diagnosticsPath] ne "absolute"} {
        set diagnosticsPath [file join $scriptDir $diagnosticsPath]
    }
    set diagnostics [tDiagnostics new $diagnosticsPath \
        [$config get Diagnostics.enabled true] \
        [$config get Diagnostics.max_events 5000]]
    set diagnosticsRefreshInterval [$config get \
        Diagnostics.refresh_interval_ms 10000]
    if {![string is integer -strict $diagnosticsRefreshInterval]
            || $diagnosticsRefreshInterval < 1000} {
        error "Diagnostics.refresh_interval_ms must be an integer of at least 1000"
    }
    set changeTrackingEnabled [$config get ChangeTracking.enabled true]
    if {![string is boolean -strict $changeTrackingEnabled]} {
        error "ChangeTracking.enabled must be boolean"
    }
    if {$changeTrackingEnabled} {
        set excluded [::parsePluginNames [$config get \
            ChangeTracking.excluded_directories ".git,.hg,.svn,.oodz"]]
        set changeTracker [tWorkspaceChangeTracker new $workspaceRoot $excluded \
            [$config get ChangeTracking.max_hash_bytes 4194304]]
    }
    set instructions [::loadWorkspaceInstructions $workspaceRoot [$config get Workspace.instructions ""] [$config get Workspace.instructions_max_file_bytes 16384]]
    set referenceRoots [dict create]
    set oodzRoot [::resolveOptionalReferenceRoot $scriptDir [$config get OODZ.root ""] OODZ.root]
    if {$oodzRoot ne ""} {
        dict set referenceRoots oodz $oodzRoot
    }
    set client [tLLMClient new $config]
    $client setDiagnostics $diagnostics
    set skillRegistry [tSkillRegistry new [::resolveSkillDirectories $scriptDir [$config get Skills.directories ""]] [$config get Skills.max_file_bytes 65536]]
    set instructionRegistry [tInstructionRegistry new $workspaceRoot [$config get Workspace.instructions ""] [$config get Workspace.instructions_max_file_bytes 16384] [$config get Workspace.instructions_max_total_bytes 65536]]
    set runnerEnabled [$config get Runner.enabled false]
    if {![string is boolean -strict $runnerEnabled]} {
        error "Runner.enabled must be boolean"
    }
    set projectTestsEnabled false
    set commandDirectories [::configuredCommandDirectories \
        $config $workspaceRoot]
    if {$runnerEnabled} {
        set processRunner [tProcessRunner new $workspaceRoot [$config get Runner.tclsh tclsh9.0] [$config get Runner.timeout_ms 10000] [$config get Runner.max_output_chars 65536] "" [dict create fossil [$config get Executables.fossil fossil]] $commandDirectories]
        set projectTestsEnabled [$config get Runner.project_tests_enabled false]
        if {![string is boolean -strict $projectTestsEnabled]} {
            error "Runner.project_tests_enabled must be boolean"
        }
        if {$projectTestsEnabled} {
            $processRunner configureProjectTests [$config get Runner.project_tests_executable ""] [$config get Runner.project_tests_arguments ""] [$config get Runner.project_tests_timeout_ms 60000]
        }
    }
    set commandExecutionEnabled [$config get CommandExecution.enabled false]
    if {![string is boolean -strict $commandExecutionEnabled]} {
        error "CommandExecution.enabled must be boolean"
    }
    if {$commandExecutionEnabled} {
        set commandMode [string tolower [string trim \
            [$config get CommandExecution.mode allowlist]]]
        set commandApproval [string tolower [string trim \
            [$config get CommandExecution.approval always]]]
        if {$commandApproval ne "always"} {
            error "CommandExecution.approval currently supports only: always"
        }
        set commandTimeout [$config get CommandExecution.timeout_ms 60000]
        set commandMaxTimeout [$config get \
            CommandExecution.max_timeout_ms 600000]
        set commandMaxOutput [$config get \
            CommandExecution.max_output_chars 1048576]
        set commandRunner [tProcessRunner new $workspaceRoot \
            [$config get Runner.tclsh tclsh9.0] \
            $commandTimeout $commandMaxOutput]
        set commandExecutor [tCommandExecutor new $workspaceRoot \
            $commandRunner $commandMode [::buildCommandPolicies $config] \
            $commandTimeout $commandMaxTimeout $commandMaxOutput]
    }
    set pluginLazyLoading [$config get Plugins.lazy_loading true]
    if {![string is boolean -strict $pluginLazyLoading]} {
        error "Plugins.lazy_loading must be boolean"
    }
    set pluginDirectories [::resolvePluginDirectories $scriptDir [$config get Plugins.directories ""]]
    set pluginCore [::loadCorePlugins $scriptDir $pluginDirectories]
    set workerEnabled [$config get Plugins.worker_thread true]
    if {![string is boolean -strict $workerEnabled]} {
        error "Plugins.worker_thread must be boolean"
    }
    if {$workerEnabled} {
        set runnerConfig [dict create enabled $runnerEnabled tclsh [$config get Runner.tclsh tclsh9.0] timeout_ms [$config get Runner.timeout_ms 10000] max_output_chars [$config get Runner.max_output_chars 65536] \
            executable_aliases [dict create fossil [$config get Executables.fossil fossil]] project_tests_enabled $projectTestsEnabled project_tests_executable [$config get Runner.project_tests_executable tclsh9.0] \
            command_directories $commandDirectories \
            project_tests_arguments [$config get Runner.project_tests_arguments tests/all.tcl] project_tests_timeout_ms [$config get Runner.project_tests_timeout_ms 60000]]
        set pluginWorker [tPluginWorker new $scriptDir $workspaceRoot $pluginDirectories [$config get Plugins.timeout_ms 1000] [$config get Plugins.max_output_chars 65536] $referenceRoots $runnerConfig]
    }
    set modelInfoCallback ""
    if {"modelInfo" in [info object methods $client -all]} {
        set modelInfoCallback [list $client modelInfo]
    }
    set registry [tPluginRegistry new $workspaceRoot $pluginDirectories ::oodzGui::approve [$config get Plugins.timeout_ms 1000] \
        [$config get Plugins.max_output_chars 65536] $referenceRoots $skillRegistry $instructionRegistry $processRunner $pluginLazyLoading $pluginCore "" $pluginWorker $modelInfoCallback $commandExecutor]
    set systemRole [::buildAgentSystemRole $config $instructions [$skillRegistry summaries] [$instructionRegistry enabled] $runnerEnabled $pluginLazyLoading]
    set systemRole [::addModelIdentityToSystemRole $systemRole $client]
    set agent [tAgent new [$config get Agent.name] $systemRole $client $registry [$config get Agent.max_iterations 24] ::oodzGui::streamChunk [$config get Agent.max_history_messages 200] [$config get Agent.summarize_history true] [$config get Agent.max_history_chars 60000]]
    $agent setDiagnostics $diagnostics
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
