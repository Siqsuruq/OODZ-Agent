package require inifile
package require json

namespace eval ::PluginSupport {
    proc commaList {value} {
        set result {}
        foreach item [split $value ,] {
            set item [string tolower [string trim $item]]
            if {$item ne "" && $item ni $result} {
                lappend result $item
            }
        }
        return $result
    }

    proc currentPlatform {} {
        set os [string tolower $::tcl_platform(os)]
        if {[string match "windows*" $os]} {
            return windows
        }
        if {$os eq "freebsd"} {
            return freebsd
        }
        if {$os eq "linux"} {
            return linux
        }
        return $os
    }

    proc isWithin {path root} {
        set pathParts [file split [file normalize $path]]
        set rootParts [file split [file normalize $root]]
        if {[llength $pathParts] < [llength $rootParts]} {
            return 0
        }
        set ignoreCase [expr {$::tcl_platform(platform) eq "windows"}]
        for {set index 0} {$index < [llength $rootParts]} {incr index} {
            set pathPart [lindex $pathParts $index]
            set rootPart [lindex $rootParts $index]
            if {$ignoreCase} {
                if {![string equal -nocase $pathPart $rootPart]} {
                    return 0
                }
            } elseif {$pathPart ne $rootPart} {
                return 0
            }
        }
        return 1
    }

    proc resolveWorkspacePath {workspaceRoot relativePath} {
        if {[file pathtype $relativePath] ne "relative"} {
            error "Plugin paths must be relative to the workspace"
        }

        set resolved [file normalize [file join $workspaceRoot $relativePath]]
        if {![::PluginSupport::isWithin $resolved $workspaceRoot]} {
            error "Plugin path escapes the workspace"
        }
        return $resolved
    }

    proc resolveReferencePath {referenceRoots referenceName relativePath} {
        if {![dict exists $referenceRoots $referenceName]} {
            error "Reference root is not configured: $referenceName"
        }
        if {[file pathtype $relativePath] ne "relative"} {
            error "Reference paths must be relative: $referenceName"
        }
        set root [dict get $referenceRoots $referenceName]
        set resolved [file normalize [file join $root $relativePath]]
        if {![::PluginSupport::isWithin $resolved $root]} {
            error "Reference path escapes configured root: $referenceName"
        }
        return $resolved
    }

    proc formatProcessResult {result} {
        foreach key {status exit_code output duration_ms timed_out
                output_truncated} {
            if {![dict exists $result $key]} {
                error "Invalid process result: missing $key"
            }
        }
        set output [dict get $result output]
        if {[dict get $result status] eq "exited"
                && [dict get $result exit_code] == 0} {
            return [expr {$output eq ""
                ? "(process completed with no output)" : $output}]
        }
        switch -- [dict get $result status] {
            timeout {
                set message "Process timed out after [dict get $result duration_ms] ms"
            }
            output_limit {
                set message "Process output exceeds limit"
            }
            default {
                set message "Process failed with exit code [dict get $result exit_code]"
            }
        }
        if {$output ne ""} {
            append message ": $output"
        }
        error $message
    }
}

::oo::class create tPluginRegistry {
    variable workspaceRoot plugins approvalCallback executionTimeout maxOutput
    variable pluginInterpreter
    variable referenceRoots
    variable skillRegistry
    variable instructionRegistry
    variable processRunner
    variable lazyLoading corePlugins activePlugins
    variable currentPlatform unavailablePlugins
    variable pluginWorker
    variable modelInfoCallback

    constructor {
        configuredWorkspaceRoot pluginDirectories
        {configuredApprovalCallback ""}
        {configuredExecutionTimeout 1000}
        {configuredMaxOutput 65536}
        {configuredReferenceRoots {}}
        {configuredSkillRegistry ""}
        {configuredInstructionRegistry ""}
        {configuredProcessRunner ""}
        {configuredLazyLoading false}
        {configuredCorePlugins {}}
        {configuredPlatform ""}
        {configuredPluginWorker ""} {configuredModelInfoCallback ""}
    } {
        set workspaceRoot [file normalize $configuredWorkspaceRoot]
        if {![file isdirectory $workspaceRoot]} {
            error "Plugin workspace root is not a directory"
        }
        if {![string is entier -strict $configuredExecutionTimeout]
                || $configuredExecutionTimeout <= 0} {
            error "Plugin timeout must be a positive integer"
        }
        if {![string is entier -strict $configuredMaxOutput]
                || $configuredMaxOutput <= 0} {
            error "Plugin output limit must be a positive integer"
        }

        set approvalCallback $configuredApprovalCallback
        set executionTimeout $configuredExecutionTimeout
        set maxOutput $configuredMaxOutput
        set referenceRoots $configuredReferenceRoots
        set skillRegistry $configuredSkillRegistry
        if {$skillRegistry ne ""
                && ![info object isa typeof $skillRegistry tSkillRegistry]} {
            error "Invalid skill registry"
        }
        set instructionRegistry $configuredInstructionRegistry
        if {$instructionRegistry ne ""
                && ![info object isa typeof \
                    $instructionRegistry tInstructionRegistry]} {
            error "Invalid instruction registry"
        }
        set processRunner $configuredProcessRunner
        if {$processRunner ne ""
                && ![info object isa typeof $processRunner tProcessRunner]} {
            error "Invalid process runner"
        }
        if {![string is boolean -strict $configuredLazyLoading]} {
            error "Plugin lazy_loading must be boolean"
        }
        set lazyLoading [expr {$configuredLazyLoading ? 1 : 0}]
        set corePlugins [lsort -unique $configuredCorePlugins]
        set activePlugins [dict create]
        set currentPlatform [string tolower [string trim $configuredPlatform]]
        if {$currentPlatform eq ""} {
            set currentPlatform [::PluginSupport::currentPlatform]
        }
        set unavailablePlugins [dict create]
        set pluginWorker $configuredPluginWorker
        set modelInfoCallback $configuredModelInfoCallback
        if {$pluginWorker ne ""
                && ![info object isa typeof $pluginWorker tPluginWorker]} {
            error "Invalid plugin worker"
        }
        dict for {referenceName referenceRoot} $referenceRoots {
            if {![regexp {^[a-z][a-z0-9_]*$} $referenceName]} {
                error "Invalid reference root name: $referenceName"
            }
            set normalizedRoot [file normalize $referenceRoot]
            if {![file isdirectory $normalizedRoot]} {
                error "Reference root is not a directory: $referenceName"
            }
            dict set referenceRoots $referenceName $normalizedRoot
        }
        set plugins [dict create]
        set pluginInterpreter [interp create]
        interp eval $pluginInterpreter {namespace eval ::PluginSupport {}}
        interp alias $pluginInterpreter \
            ::PluginSupport::resolveWorkspacePath {} \
            ::PluginSupport::resolveWorkspacePath
        interp alias $pluginInterpreter \
            ::PluginSupport::isWithin {} \
            ::PluginSupport::isWithin
        interp alias $pluginInterpreter \
            ::PluginSupport::resolveReferencePath {} \
            ::PluginSupport::resolveReferencePath $referenceRoots
        interp alias $pluginInterpreter \
            ::PluginSupport::formatProcessResult {} \
            ::PluginSupport::formatProcessResult
        if {$processRunner ne ""} {
            interp alias $pluginInterpreter \
                ::PluginSupport::runConfiguredCommand {} \
                $processRunner runConfiguredCommand
        } else {
            interp eval $pluginInterpreter {
                proc ::PluginSupport::runConfiguredCommand {args} {
                    error "Configured process runner is not enabled"
                }
            }
        }

        foreach pluginDirectory $pluginDirectories {
            my discover $pluginDirectory
        }
        foreach name $corePlugins {
            if {![dict exists $plugins $name]} {
                error "Unknown core plugin: $name"
            }
            dict set activePlugins $name 1
        }
    }

    destructor {
        if {[info exists pluginInterpreter]
                && [interp exists $pluginInterpreter]} {
            interp delete $pluginInterpreter
        }
    }

    method discover {pluginDirectory} {
        set pluginRoot [file normalize $pluginDirectory]
        if {![file isdirectory $pluginRoot]} {
            error "Plugin directory does not exist: $pluginDirectory"
        }

        foreach candidate [lsort [glob -nocomplain \
                -types d -directory $pluginRoot *]] {
            set pluginPath [file normalize $candidate]
            if {![::PluginSupport::isWithin $pluginPath $pluginRoot]} {
                error "Plugin directory escapes configured root: $candidate"
            }

            set manifestPath [file join $pluginPath plugin.ini]
            if {[file isfile $manifestPath]} {
                my loadPlugin $pluginRoot $pluginPath $manifestPath
            }
        }
    }

    method loadPlugin {pluginRoot pluginPath manifestPath} {
        set manifest [my readManifest $manifestPath]
        foreach key {name description permission entrypoint handler parameters} {
            if {![dict exists $manifest $key]
                    || [string trim [dict get $manifest $key]] eq ""} {
                error "Invalid plugin manifest: missing $key"
            }
        }

        set name [dict get $manifest name]
        if {![regexp {^[a-z][a-z0-9_]*$} $name]} {
            error "Invalid plugin name: $name"
        }
        if {[dict exists $plugins $name]
                || [dict exists $unavailablePlugins $name]} {
            error "Duplicate plugin name: $name"
        }

        set permission [dict get $manifest permission]
        if {$permission ni {read write}} {
            error "Invalid plugin permission for $name: $permission"
        }

        foreach {key defaultValue} {
            platforms all
            requires {}
            category general
            keywords {}
        } {
            if {![dict exists $manifest $key]} {
                dict set manifest $key $defaultValue
            }
        }
        set category [string tolower [string trim \
            [dict get $manifest category]]]
        if {![regexp {^[a-z][a-z0-9_-]*$} $category]} {
            error "Invalid plugin category for $name: $category"
        }
        dict set manifest category $category
        set platforms [::PluginSupport::commaList \
            [dict get $manifest platforms]]
        if {[llength $platforms] == 0} {
            error "Invalid plugin platforms for $name"
        }
        foreach platform $platforms {
            if {$platform ni {all linux freebsd windows}} {
                error "Invalid plugin platform for $name: $platform"
            }
        }
        dict set manifest platforms $platforms
        set requirements [::PluginSupport::commaList \
            [dict get $manifest requires]]
        foreach requirement $requirements {
            if {![regexp {^[a-z0-9_.+:-]+$} $requirement]} {
                error "Invalid plugin requirement for $name: $requirement"
            }
        }
        dict set manifest requires $requirements
        dict set manifest keywords [::PluginSupport::commaList \
            [dict get $manifest keywords]]

        if {"all" ni $platforms && $currentPlatform ni $platforms} {
            dict set unavailablePlugins $name \
                "unsupported platform: $currentPlatform"
            return
        }
        foreach requirement $requirements {
            if {[auto_execok $requirement] eq ""} {
                dict set unavailablePlugins $name \
                    "missing executable: $requirement"
                return
            }
        }

        set entrypoint [dict get $manifest entrypoint]
        if {[file tail $entrypoint] ne $entrypoint} {
            error "Plugin entrypoint must be a filename: $name"
        }
        set implementationPath [file normalize \
            [file join $pluginPath $entrypoint]]
        if {![::PluginSupport::isWithin $implementationPath $pluginPath]
                || ![file isfile $implementationPath]} {
            error "Plugin entrypoint is invalid: $name"
        }

        set parametersJson [dict get $manifest parameters]
        if {[catch {::json::json2dict $parametersJson} parameters]} {
            error "Invalid plugin parameter schema: $name"
        }
        if {![dict exists $parameters type]
                || [dict get $parameters type] ne "object"} {
            error "Plugin parameter schema must describe an object: $name"
        }

        set handler [dict get $manifest handler]
        interp eval $pluginInterpreter [list source $implementationPath]
        if {[llength [interp eval $pluginInterpreter \
                [list info commands $handler]]] != 1} {
            error "Plugin handler is not defined: $name"
        }

        dict set manifest parameters_schema $parameters
        dict set manifest plugin_path $pluginPath
        dict set plugins $name $manifest
    }

    method readManifest {manifestPath} {
        set ini [::ini::open $manifestPath r]
        try {
            if {"plugin" ni [::ini::sections $ini]} {
                error "Invalid plugin manifest: missing plugin section"
            }
            set manifest [dict create]
            foreach key [::ini::keys $ini plugin] {
                dict set manifest $key [::ini::value $ini plugin $key]
            }
            set settings [dict create]
            if {"settings" in [::ini::sections $ini]} {
                foreach key [::ini::keys $ini settings] {
                    dict set settings $key \
                        [::ini::value $ini settings $key]
                }
            }
            dict set manifest settings $settings
            return $manifest
        } finally {
            ::ini::close $ini
        }
    }

    method names {} {
        set names [dict keys $plugins]
        if {$modelInfoCallback ne ""} {
            lappend names model_info
        }
        if {$skillRegistry ne ""} {
            lappend names load_skill
        }
        if {$instructionRegistry ne "" && [$instructionRegistry enabled]} {
            lappend names load_project_instructions
        }
        if {$processRunner ne ""} {
            lappend names run_tcl_file
            if {[$processRunner hasProjectTests]} {
                lappend names run_project_tests
            }
        }
        return [lsort $names]
    }

    method unavailable {} {
        return $unavailablePlugins
    }

    method definitions {} {
        set definitions {}
        if {$lazyLoading} {
            set visibleNames [my specialNames]
            lappend visibleNames search_plugins
            dict for {name enabled} $activePlugins {
                lappend visibleNames $name
            }
            set visibleNames [lsort -unique $visibleNames]
        } else {
            set visibleNames [my names]
        }
        foreach name $visibleNames {
            if {$name eq "search_plugins"} {
                set parametersJson {{"type":"object","properties":{"query":{"type":"string","description":"Words describing the capability or exact plugin name to find."},"limit":{"type":"integer","minimum":1,"maximum":10}},"required":["query"],"additionalProperties":false}}
                lappend definitions [dict create \
                    name search_plugins \
                    description "Search the installed plugin index and activate matching tools for the next response." \
                    parameters [::json::json2dict $parametersJson] \
                    parameters_json $parametersJson]
                continue
            }
            if {$name eq "model_info"} {
                set parametersJson {{"type":"object","properties":{},"required":[],"additionalProperties":false}}
                lappend definitions [dict create \
                    name model_info \
                    description "Report the configured LLM provider and model plus the model identifier most recently returned by the API. No credentials or endpoint details are exposed." \
                    parameters [::json::json2dict $parametersJson] \
                    parameters_json $parametersJson]
                continue
            }
            if {$name eq "load_skill"} {
                set parametersJson {{"type":"object","properties":{"name":{"type":"string"}},"required":["name"],"additionalProperties":false}}
                lappend definitions [dict create \
                    name load_skill \
                    description "Load the complete instructions for one available skill when its description matches the current task." \
                    parameters [::json::json2dict $parametersJson] \
                    parameters_json $parametersJson]
                continue
            }
            if {$name eq "load_project_instructions"} {
                set parametersJson {{"type":"object","properties":{"path":{"type":"string"}},"required":["path"],"additionalProperties":false}}
                lappend definitions [dict create \
                    name load_project_instructions \
                    description "Load hierarchical project instruction files for a workspace-relative file or directory before modifying content in that subtree." \
                    parameters [::json::json2dict $parametersJson] \
                    parameters_json $parametersJson]
                continue
            }
            if {$name eq "run_tcl_file"} {
                set parametersJson {{"type":"object","properties":{"path":{"type":"string"}},"required":["path"],"additionalProperties":false}}
                set description "Run one existing workspace-relative .tcl file directly with the agent user's full OS permissions. There is no OS sandbox; the script may access files, processes, network, and environment. Every run requires approval."
                lappend definitions [dict create \
                    name run_tcl_file \
                    description $description \
                    parameters [::json::json2dict $parametersJson] \
                    parameters_json $parametersJson]
                continue
            }
            if {$name eq "run_project_tests"} {
                set parametersJson {{"type":"object","properties":{},"required":[],"additionalProperties":false}}
                set description "Run the fixed project-test command from trusted configuration directly with the agent user's full OS permissions. The model cannot choose its executable or arguments. Every run requires approval."
                lappend definitions [dict create \
                    name run_project_tests \
                    description $description \
                    parameters [::json::json2dict $parametersJson] \
                    parameters_json $parametersJson]
                continue
            }
            set plugin [dict get $plugins $name]
            lappend definitions [dict create \
                name $name \
                description [dict get $plugin description] \
                parameters [dict get $plugin parameters_schema] \
                parameters_json [dict get $plugin parameters]]
        }
        return $definitions
    }

    method invoke {name argumentsJson} {
        if {$name eq "model_info" && $modelInfoCallback ne ""} {
            if {[catch {::json::json2dict $argumentsJson} arguments]} {
                error "Invalid JSON arguments for plugin: $name"
            }
            my validateArguments $name $arguments \
                [dict create properties [dict create] required {}]
            set information [{*}$modelInfoCallback]
            return [join [list \
                "Provider: [dict get $information provider]" \
                "Configured model: [dict get $information configured_model]" \
                "API-reported model: [dict get $information reported_model]"] "\n"]
        }
        if {$name eq "search_plugins" && $lazyLoading} {
            if {[catch {::json::json2dict $argumentsJson} arguments]} {
                error "Invalid JSON arguments for plugin: $name"
            }
            set schema [dict create \
                properties [dict create \
                    query [dict create type string] \
                    limit [dict create type integer minimum 1 maximum 10]] \
                required [list query]]
            my validateArguments $name $arguments $schema
            set query [string trim [dict get $arguments query]]
            if {$query eq ""} {
                error "Plugin search query must not be empty"
            }
            set limit 5
            if {[dict exists $arguments limit]} {
                set limit [dict get $arguments limit]
                if {![string is entier -strict $limit]
                        || $limit < 1 || $limit > 10} {
                    error "Plugin search limit must be an integer from 1 to 10"
                }
            }
            set matches [my search $query $limit]
            if {[llength $matches] == 0} {
                return "No installed plugins matched: $query"
            }
            set lines {}
            foreach match $matches {
                set pluginName [dict get $match name]
                dict set activePlugins $pluginName 1
                lappend lines "$pluginName - [dict get $match description]"
            }
            return "Activated plugins:\n[join $lines \n]"
        }
        if {$name eq "load_skill" && $skillRegistry ne ""} {
            if {[catch {::json::json2dict $argumentsJson} arguments]} {
                error "Invalid JSON arguments for plugin: $name"
            }
            set schema [dict create \
                properties [dict create name [dict create type string]] \
                required [list name]]
            my validateArguments $name $arguments $schema
            set skill [$skillRegistry get [dict get $arguments name]]
            return [dict get $skill instructions]
        }
        if {$name eq "load_project_instructions"
                && $instructionRegistry ne ""} {
            if {[catch {::json::json2dict $argumentsJson} arguments]} {
                error "Invalid JSON arguments for plugin: $name"
            }
            set schema [dict create \
                properties [dict create path [dict create type string]] \
                required [list path]]
            my validateArguments $name $arguments $schema
            return [$instructionRegistry loadForPath \
                [dict get $arguments path]]
        }
        if {$name eq "run_tcl_file" && $processRunner ne ""} {
            if {[catch {::json::json2dict $argumentsJson} arguments]} {
                error "Invalid JSON arguments for plugin: $name"
            }
            set schema [dict create \
                properties [dict create path [dict create type string]] \
                required [list path]]
            my validateArguments $name $arguments $schema
            my requireWriteApproval $name $arguments
            return [::PluginSupport::formatProcessResult \
                [$processRunner runTclFile [dict get $arguments path]]]
        }
        if {$name eq "run_project_tests" && $processRunner ne ""
                && [$processRunner hasProjectTests]} {
            if {[catch {::json::json2dict $argumentsJson} arguments]} {
                error "Invalid JSON arguments for plugin: $name"
            }
            set schema [dict create properties [dict create] required {}]
            my validateArguments $name $arguments $schema
            my requireWriteApproval $name $arguments
            return [::PluginSupport::formatProcessResult \
                [$processRunner runProjectTests]]
        }
        if {![dict exists $plugins $name]} {
            error "Unknown plugin: $name"
        }
        if {[catch {::json::json2dict $argumentsJson} arguments]} {
            error "Invalid JSON arguments for plugin: $name"
        }

        set plugin [dict get $plugins $name]
        my validateArguments \
            $name $arguments [dict get $plugin parameters_schema]

        if {[dict get $plugin permission] eq "write"} {
            my requireWriteApproval $name $arguments
        }

        if {$pluginWorker ne ""} {
            return [$pluginWorker invoke $name $argumentsJson]
        }

        set handler [dict get $plugin handler]
        set deadline [expr {[clock milliseconds] + $executionTimeout}]
        interp limit $pluginInterpreter time \
            -seconds [expr {$deadline / 1000}] \
            -milliseconds [expr {$deadline % 1000}]
        set invocationCode [catch {
            interp eval $pluginInterpreter \
                [list $handler $workspaceRoot $arguments \
                    [dict get $plugin settings]]
        } result options]
        interp limit $pluginInterpreter time \
            -seconds {} \
            -milliseconds {}

        if {$invocationCode} {
            if {[dict exists $options -errorcode]
                    && [dict get $options -errorcode] eq "TCL LIMIT TIME"} {
                error "Plugin execution timed out: $name"
            }
            return -options $options $result
        }
        if {[string length $result] > $maxOutput} {
            error "Plugin output exceeds limit: $name"
        }
        return $result
    }

    method invokeForModel {name argumentsJson} {
        if {$lazyLoading} {
            set visible 0
            foreach definition [my definitions] {
                if {[dict get $definition name] eq $name} {
                    set visible 1
                    break
                }
            }
            if {!$visible} {
                error "Plugin is not active for the model: $name"
            }
        }
        return [my invoke $name $argumentsJson]
    }

    method specialNames {} {
        set result {}
        if {$modelInfoCallback ne ""} {
            lappend result model_info
        }
        if {$skillRegistry ne ""} {
            lappend result load_skill
        }
        if {$instructionRegistry ne "" && [$instructionRegistry enabled]} {
            lappend result load_project_instructions
        }
        if {$processRunner ne ""} {
            lappend result run_tcl_file
            if {[$processRunner hasProjectTests]} {
                lappend result run_project_tests
            }
        }
        return $result
    }

    method search {query {limit 5}} {
        set terms [regexp -all -inline {[a-z0-9]+} [string tolower $query]]
        set ranked {}
        dict for {name plugin} $plugins {
            set description [dict get $plugin description]
            set haystack [string tolower [join [list \
                $name $description [dict get $plugin category] \
                {*}[dict get $plugin keywords]] " "]]
            set score 0
            foreach term $terms {
                if {[string first $term $haystack] >= 0} {
                    incr score
                }
            }
            if {[string equal -nocase [string trim $query] $name]} {
                incr score 10
            }
            if {$score > 0} {
                lappend ranked [list [expr {-$score}] $name $description]
            }
        }
        set result {}
        foreach item [lrange [lsort -integer -index 0 $ranked] 0 \
                [expr {$limit - 1}]] {
            lappend result [dict create \
                name [lindex $item 1] description [lindex $item 2]]
        }
        return $result
    }

    method requireWriteApproval {name arguments} {
        if {$approvalCallback eq ""} {
            error "Plugin approval required: $name"
        }
        set approved [{*}$approvalCallback $name $arguments]
        if {![string is boolean -strict $approved] || !$approved} {
            error "Plugin execution denied: $name"
        }
    }

    method validateArguments {name arguments schema} {
        set properties [dict create]
        if {[dict exists $schema properties]} {
            set properties [dict get $schema properties]
        }

        if {[dict exists $schema required]} {
            foreach key [dict get $schema required] {
                if {![dict exists $arguments $key]} {
                    error "Missing plugin argument for $name: $key"
                }
            }
        }

        dict for {key value} $arguments {
            if {![dict exists $properties $key]} {
                error "Unknown plugin argument for $name: $key"
            }
            set property [dict get $properties $key]
            if {[dict exists $property type]
                    && [dict get $property type] eq "string"
                    && [catch {string length $value}]} {
                error "Plugin argument must be a string for $name: $key"
            }
        }
    }
}
