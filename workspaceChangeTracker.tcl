::oo::class create tWorkspaceChangeTracker {
    variable workspaceRoot excludedDirectories excludedFiles maxHashBytes

    constructor {configuredRoot {configuredExcludedDirectories {}}
        {configuredMaxHashBytes 4194304}} {
        set workspaceRoot [file normalize $configuredRoot]
        if {![file isdirectory $workspaceRoot]} {
            error "Change-tracking root is not a directory"
        }
        if {![string is entier -strict $configuredMaxHashBytes]
                || $configuredMaxHashBytes < 0} {
            error "ChangeTracking.max_hash_bytes must be a non-negative integer"
        }
        set excludedDirectories $configuredExcludedDirectories
        set excludedFiles [list .fslckout _FOSSIL_]
        set maxHashBytes $configuredMaxHashBytes
    }

    method relative {path} {
        if {$path eq $workspaceRoot} {return .}
        return [string range $path [expr {[string length $workspaceRoot] + 1}] end]
    }

    method fingerprint {path} {
        set size [file size $path]
        set result [list size $size mtime [file mtime $path]]
        if {$size <= $maxHashBytes} {
            set channel [open $path rb]
            try {
                set checksum 0
                while {![eof $channel]} {
                    set checksum [zlib crc32 [read $channel 65536] $checksum]
                }
            } finally {
                close $channel
            }
            lappend result crc32 $checksum
        }
        if {![catch {file attributes $path -permissions} permissions]} {
            lappend result permissions $permissions
        }
        return $result
    }

    method scanDirectory {directory snapshotVariable} {
        upvar 1 $snapshotVariable result
        set entries [lsort -unique [concat [glob -nocomplain -directory $directory *] [glob -nocomplain -directory $directory .*]]]
        foreach path $entries {
            set tail [file tail $path]
            if {$tail in {. ..}} {continue}
            if {[file type $path] eq "link"} {continue}
            if {[file isdirectory $path]} {
                if {$tail ni $excludedDirectories} {
                    my scanDirectory $path result
                }
                continue
            }
            if {$tail in $excludedFiles || ![file isfile $path]} {continue}
            if {[catch {my fingerprint $path} fingerprint]} {continue}
            dict set result [my relative $path] $fingerprint
        }
    }

    method snapshot {} {
        set result [dict create]
        my scanDirectory $workspaceRoot result
        return $result
    }

    method compare {before after} {
        set added {}
        set modified {}
        set deleted {}
        dict for {path fingerprint} $after {
            if {![dict exists $before $path]} {
                lappend added $path
            } elseif {[dict get $before $path] ne $fingerprint} {
                lappend modified $path
            }
        }
        dict for {path fingerprint} $before {
            if {![dict exists $after $path]} {
                lappend deleted $path
            }
        }
        return [dict create added [lsort $added] modified [lsort $modified] deleted [lsort $deleted]]
    }

    method format {changes} {
        set lines {}
        foreach {field label marker} {
            added Added + modified Modified ~ deleted Deleted -
        } {
            foreach path [dict get $changes $field] {
                lappend lines "$marker $label: $path"
            }
        }
        return [join $lines "\n"]
    }
}
