::oo::class create tSkillRegistry {
    variable skills maxSkillBytes

    constructor {skillDirectories {configuredMaxSkillBytes 65536}} {
        if {![string is entier -strict $configuredMaxSkillBytes]
                || $configuredMaxSkillBytes <= 0} {
            error "Skill size limit must be a positive integer"
        }
        set maxSkillBytes $configuredMaxSkillBytes
        set skills [dict create]
        foreach directory $skillDirectories {
            my discover $directory
        }
    }

    method discover {skillDirectory} {
        set root [file normalize $skillDirectory]
        if {![file isdirectory $root]} {
            error "Skill directory does not exist: $skillDirectory"
        }
        foreach candidate [lsort [glob -nocomplain \
                -types d -directory $root *]] {
            set skillPath [file normalize $candidate]
            if {![my isWithin $skillPath $root]} {
                error "Skill directory escapes configured root: $candidate"
            }
            set instructionPath [file join $skillPath SKILL.md]
            if {[file isfile $instructionPath]} {
                my loadSkill $skillPath $instructionPath
            }
        }
    }

    method loadSkill {skillPath instructionPath} {
        if {[file size $instructionPath] > $maxSkillBytes} {
            error "Skill file exceeds size limit: $instructionPath"
        }
        set channel [open $instructionPath r]
        try {
            fconfigure $channel -encoding utf-8 -translation lf
            set source [read $channel]
        } finally {
            close $channel
        }
        set parsed [my parseSkill $source $instructionPath]
        set name [dict get $parsed name]
        if {[file tail $skillPath] ne $name} {
            error "Skill folder must match skill name: $name"
        }
        if {[dict exists $skills $name]} {
            error "Duplicate skill name: $name"
        }
        dict set parsed path $skillPath
        dict set parsed instruction_path $instructionPath
        dict set skills $name $parsed
    }

    method parseSkill {source instructionPath} {
        set lines [split $source "\n"]
        if {[llength $lines] < 4 || [string trim [lindex $lines 0]] ne "---"} {
            error "Invalid skill frontmatter: $instructionPath"
        }
        set closingIndex -1
        for {set index 1} {$index < [llength $lines]} {incr index} {
            if {[string trim [lindex $lines $index]] eq "---"} {
                set closingIndex $index
                break
            }
        }
        if {$closingIndex < 0} {
            error "Invalid skill frontmatter: $instructionPath"
        }

        set metadata [dict create]
        foreach line [lrange $lines 1 [expr {$closingIndex - 1}]] {
            if {[string trim $line] eq ""} {
                continue
            }
            if {![regexp {^([a-z][a-z0-9_-]*):[[:space:]]*(.+)$} \
                    $line -> key value]} {
                error "Invalid skill metadata: $instructionPath"
            }
            if {$key ni {name description}} {
                error "Unsupported skill metadata field: $key"
            }
            if {[dict exists $metadata $key]} {
                error "Duplicate skill metadata field: $key"
            }
            dict set metadata $key [string trim $value]
        }
        foreach key {name description} {
            if {![dict exists $metadata $key]
                    || [string trim [dict get $metadata $key]] eq ""} {
                error "Invalid skill metadata: missing $key"
            }
        }
        set name [dict get $metadata name]
        if {![regexp {^[a-z][a-z0-9-]{0,63}$} $name]} {
            error "Invalid skill name: $name"
        }
        set instructions [string trim \
            [join [lrange $lines [expr {$closingIndex + 1}] end] "\n"]]
        if {$instructions eq ""} {
            error "Skill instructions must not be empty: $name"
        }
        dict set metadata instructions $instructions
        return $metadata
    }

    method names {} {
        return [lsort [dict keys $skills]]
    }

    method summaries {} {
        set summaries {}
        foreach name [my names] {
            lappend summaries [dict create \
                name $name \
                description [dict get $skills $name description]]
        }
        return $summaries
    }

    method get {name} {
        if {![dict exists $skills $name]} {
            error "Unknown skill: $name"
        }
        return [dict get $skills $name]
    }

    method isWithin {path root} {
        ::PluginSupport::isWithin $path $root
    }
}
