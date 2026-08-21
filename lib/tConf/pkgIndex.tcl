# pkgIndex.tcl
# Explicitly source your enterprise files in order using the native $dir variable
package ifneeded tConfClass 1.0.0 [subst {
    source [file join $dir tConfClass.tcl]
    source [file join $dir backends ini.tcl]
}]
