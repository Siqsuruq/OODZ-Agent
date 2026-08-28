if {![package vsatisfies [package provide Tcl] 9.0-]} { return }

package ifneeded oodzMarkdownTk 0.1.0 \
    [list source [file join $dir markdownTk.tcl]]

