package require inifile
package require json

namespace eval ::PluginSupport {
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
}

::oo::class create tPluginRegistry {
    variable workspaceRoot plugins approvalCallback executionTimeout maxOutput
    variable pluginInterpreter
    variable referenceRoots
    variable skillRegistry
    variable instructionRegistry
    variable processRunner

    constructor {
        configuredWorkspaceRoot pluginDirectories
        {configuredApprovalCallback ""}
        {configuredExecutionTimeout 1000}
        {configuredMaxOutput 65536}
        {configuredReferenceRoots {}}
        {configuredSkillRegistry ""}
        {configuredInstructionRegistry ""}
        {configuredProcessRunner ""}
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
        if {[dict exists $plugins $name]} {
            error "Duplicate plugin name: $name"
        }

        set permission [dict get $manifest permission]
        if {$permission ni {read write}} {
            error "Invalid plugin permission for $name: $permission"
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

    method definitions {} {
        set definitions {}
        foreach name [my names] {
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
                if {[$processRunner mode] eq "direct"} {
                    set description "Run one existing workspace-relative .tcl file directly with the agent user's full OS permissions. There is no OS sandbox; the script may access files, processes, network, and environment. Every run requires approval."
                } else {
                    set description "Run one existing workspace-relative .tcl file in an approved Bubblewrap sandbox with no network and bounded time/output. Execution may modify workspace files."
                }
                lappend definitions [dict create \
                    name run_tcl_file \
                    description $description \
                    parameters [::json::json2dict $parametersJson] \
                    parameters_json $parametersJson]
                continue
            }
            if {$name eq "run_project_tests"} {
                set parametersJson {{"type":"object","properties":{},"required":[],"additionalProperties":false}}
                if {[$processRunner mode] eq "direct"} {
                    set description "Run the fixed project-test command from trusted configuration directly with the agent user's full OS permissions. The model cannot choose its executable or arguments. Every run requires approval."
                } else {
                    set description "Run the fixed project-test command from trusted configuration through the configured Bubblewrap runner. The model cannot choose its executable or arguments."
                }
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
            return [$processRunner runTclFile [dict get $arguments path]]
        }
        if {$name eq "run_project_tests" && $processRunner ne ""
                && [$processRunner hasProjectTests]} {
            if {[catch {::json::json2dict $argumentsJson} arguments]} {
                error "Invalid JSON arguments for plugin: $name"
            }
            set schema [dict create properties [dict create] required {}]
            my validateArguments $name $arguments $schema
            my requireWriteApproval $name $arguments
            return [$processRunner runProjectTests]
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
