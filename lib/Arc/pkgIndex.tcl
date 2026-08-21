# pkgIndex.tcl for additional tile pixmap theme Arc.
#
# We don't provide the package if we don't have the right version of Tcl/Tk
#
#  Copyright (c) 2015, 2025 Sergei Golovan <sgolovan@nes.ru>

if {![package vsatisfies [package provide Tcl] 8.6-]} { return }

package ifneeded ttk::theme::Arc 0.2 \
    [list source [file join $dir arc.tcl]]

# vim:ts=8:sw=4:sts=4:et
