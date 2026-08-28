namespace eval ::plugins::unzip {}

proc ::plugins::unzip::positiveInteger {settings name defaultValue} {
    set value $defaultValue
    if {[dict exists $settings $name]} {
        set value [dict get $settings $name]
    }
    if {![string is entier -strict $value] || $value <= 0} {
        error "unzip $name setting must be a positive integer"
    }
    return $value
}

proc ::plugins::unzip::execute {workspaceRoot arguments settings} {
    set sourceRelative [string trim [dict get $arguments source]]
    set destinationRelative [string trim [dict get $arguments destination]]
    if {$sourceRelative eq "" || $destinationRelative eq ""} {
        error "Unzip source and destination paths must not be empty"
    }
    if {[string tolower [file extension $sourceRelative]] ne ".zip"} {
        error "Unzip source must use the .zip extension"
    }

    set source [::PluginSupport::resolveWorkspacePath $workspaceRoot $sourceRelative]
    set destination [::PluginSupport::resolveWorkspacePath $workspaceRoot $destinationRelative]
    if {![file isfile $source]} {
        error "ZIP archive does not exist: $sourceRelative"
    }
    if {[file exists $destination]} {
        error "Unzip destination already exists: $destinationRelative"
    }
    if {![file isdirectory [file dirname $destination]]} {
        error "Unzip destination parent directory does not exist: [file dirname $destinationRelative]"
    }

    set maximumEntries [::plugins::unzip::positiveInteger $settings max_entries 10000]
    set maximumBytes [::plugins::unzip::positiveInteger $settings max_uncompressed_bytes 1073741824]
    set mountPoint "/oodz_unzip_[pid]_[clock clicks]"
    set mounted 0
    try {
        set archiveRoot [zipfs mount $source $mountPoint]
        set mounted 1
        set entries [zipfs list]
        set archiveEntries {}
        set topLevelEntries [dict create]
        set totalBytes 0
        foreach entry $entries {
            if {$entry eq $archiveRoot
                    || [string first "${archiveRoot}/" $entry] != 0} {
                continue
            }
            lappend archiveEntries $entry
            set relative [string range $entry [expr {[string length $archiveRoot] + 1}] end]
            dict set topLevelEntries [lindex [file split $relative] 0] 1
            if {[llength $archiveEntries] > $maximumEntries} {
                error "ZIP archive exceeds entry limit: $maximumEntries"
            }
            if {[file isfile $entry]} {
                incr totalBytes [file size $entry]
                if {$totalBytes > $maximumBytes} {
                    error "ZIP archive exceeds uncompressed size limit: $maximumBytes bytes"
                }
            }
        }

        file mkdir $destination
        dict for {topLevel ignored} $topLevelEntries {
            file copy [file join $archiveRoot $topLevel] $destination
        }
    } on error {message options} {
        if {[file exists $destination]} {
            file delete -force $destination
        }
        return -options $options $message
    } finally {
        if {$mounted} {
            catch {zipfs unmount $mountPoint}
        }
    }
    return "Extracted ZIP archive: $sourceRelative -> $destinationRelative"
}
