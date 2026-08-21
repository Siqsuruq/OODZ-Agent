# pkgIndex.tcl
# Explicitly source your enterprise files in order using the native $dir variable
package ifneeded tLogger 1.0.0 [subst {
    source [file join $dir tAppenderBase.tcl]
    source [file join $dir tStandardAppenders.tcl]
    source [file join $dir tLoggerClass.tcl]
}]
