::oo::class create tInstructionRegistry {
    variable workspaceRoot instructionName maxFileBytes maxTotalBytes

    constructor {
        configuredWorkspaceRoot configuredInstructionPath
        {configuredMaxFileBytes 16384} {configuredMaxTotalBytes 65536}
    } {
        set workspaceRoot [file normalize $configuredWorkspaceRoot]
        if {![file isdirectory $workspaceRoot]} {
            error "Instruction workspace root is not a directory"
        }
        set configuredInstructionPath [string trim $configuredInstructionPath]
        if {$configuredInstructionPath eq ""} {
            set instructionName ""
        } else {
            if {[file pathtype $configuredInstructionPath] ne "relative"} {
                error "Workspace.instructions must be relative to the workspace"
            }
            set instructionName [file tail $configuredInstructionPath]
            if {$instructionName ne $configuredInstructionPath} {
                error "Workspace.instructions must be a filename for hierarchical loading"
            }
        }
        foreach {value label} [list \
                $configuredMaxFileBytes "Instruction file size limit" \
                $configuredMaxTotalBytes "Instruction total size limit"] {
            if {![string is entier -strict $value] || $value <= 0} {
                error "$label must be a positive integer"
            }
        }
        set maxFileBytes $configuredMaxFileBytes
        set maxTotalBytes $configuredMaxTotalBytes
    }

    method enabled {} {
        expr {$instructionName ne ""}
    }

    method loadForPath {relativePath} {
        if {![my enabled]} {
            return "(project instructions are disabled)"
        }
        if {[file pathtype $relativePath] ne "relative"} {
            error "Instruction target path must be relative to the workspace"
        }
        set target [file normalize [file join $workspaceRoot $relativePath]]
        if {![::PluginSupport::isWithin $target $workspaceRoot]} {
            error "Instruction target path escapes the workspace"
        }
        if {[file isdirectory $target]} {
            set targetDirectory $target
        } else {
            set targetDirectory [file dirname $target]
        }

        set directories {}
        set relativeDirectory [string range $targetDirectory \
            [expr {[string length $workspaceRoot] + 1}] end]
        if {$targetDirectory ne $workspaceRoot} {
            set current $workspaceRoot
            foreach component [file split $relativeDirectory] {
                if {$component eq ""} {
                    continue
                }
                set current [file join $current $component]
                lappend directories $current
            }
        }

        set sections {}
        set totalBytes 0
        foreach directory $directories {
            set path [file join $directory $instructionName]
            if {![file isfile $path]} {
                continue
            }
            set fileBytes [file size $path]
            if {$fileBytes > $maxFileBytes} {
                error "Workspace instruction file exceeds $maxFileBytes bytes: [my relative $path]"
            }
            incr totalBytes $fileBytes
            if {$totalBytes > $maxTotalBytes} {
                error "Hierarchical instructions exceed $maxTotalBytes bytes"
            }
            set content [my readUtf8 $path]
            lappend sections "## [my relative $path]\n$content"
        }
        if {[llength $sections] == 0} {
            return "(no project instruction files found for $relativePath)"
        }
        return [join $sections "\n\n"]
    }

    method readUtf8 {path} {
        set channel [open $path rb]
        try {
            set bytes [read $channel]
        } finally {
            close $channel
        }
        if {[catch {encoding convertfrom utf-8 $bytes} content]} {
            error "Workspace instruction file is not valid UTF-8: [my relative $path]"
        }
        return [string trim $content]
    }

    method relative {path} {
        if {$path eq $workspaceRoot} {
            return "."
        }
        string range $path [expr {[string length $workspaceRoot] + 1}] end
    }
}
