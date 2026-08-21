# arc.tcl --
#
# Arc pixmap theme for the ttk package.
#
# Usage:
#   set ::tk_scale <num>
#   # where <num> is an integer scaling factor (1, 2, ...),
#   # it is taken from $GDK_SCALE or derived from [tk scaling]
#
#   package require ttk::themes::Arc
#
#   ttk::style theme use Arc
#   # or
#   ttk::style theme use Arc-Dark
#
#  Copyright (c) 2015, 2025 Sergei Golovan <sgolovan@nes.ru>

package require Tk 8.6-


namespace eval ::ttk::theme::Arc {

    variable version 0.2
    package provide ttk::theme::Arc $version
    package provide ttk::theme::Arc-Dark $version

    variable currentThemeForColors ""
    variable currentThemeForMenus
    array set currentThemeForMenus {}

    variable colorsLight
    array set colorsLight {
        -bg             "#f5f6f7"
        -fg             "#5c616c"
        -disabledbg     "#fbfcfc"
        -disabledfg     "#a9acb2"
        -activebg       "#ffffff"
        -activefg       "#5c616c"
        -selectbg       "#5294e2"
        -selectfg       "#ffffff"
        -window         "#ffffff"
        -focuscolor     "#5c616c"
        -checklight     "#fbfcfc"
    }

    variable colorsDark
    array set colorsDark {
        -bg             "#383c4a"
        -fg             "#d3dae3"
        -disabledbg     "#3e4350"
        -disabledfg     "#7c818c"
        -activebg       "#505666"
        -activefg       "#d3dae3"
        -selectbg       "#5294e2"
        -selectfg       "#ffffff"
        -window         "#404452"
        -focuscolor     "#d3dae3"
        -checklight     "#3e4350"
    }

    variable scale
    if {[info exists tk_scale]} {
        set scale $::tk_scale
    } elseif {[info exists ::env(GDK_SCALE)]} {
        set scale $::env(GDK_SCALE)
    } else {
        set scale [expr {([tk scaling]*72 + 32) / 96}]
    }
    if {$scale < 1} {
        set scale 1
    } else {
        set scale [expr {int($scale)}]
    }

    proc LoadImages {imgdir} {
        variable scale
        variable I
        foreach file [glob -directory $imgdir *.svg] {
            set img [file tail [file rootname $file]]
            set I($img) [image create photo -file $file -format [list svg -scale $scale]]
        }
    }

    proc s {args} {
        variable scale
        lmap x $args {expr {$scale*$x}}
    }

    proc ThemeSettings {colorsvar assetsdir} {
        upvar $colorsvar colors
        variable I

        LoadImages [file join [file dirname [info script]] $assetsdir]

        ttk::style configure . \
            -background $colors(-bg) \
            -foreground $colors(-fg) \
            -troughcolor $colors(-bg) \
            -selectbackground $colors(-selectbg) \
            -selectforeground $colors(-selectfg) \
            -fieldbackground $colors(-window) \
            -font TkDefaultFont \
            -borderwidth [s 1] \
            -focuscolor $colors(-focuscolor) \
            -focuswidth [s 2] \
            -insertcolor $colors(-fg) \
            -highlightthickness 0

        ttk::style map . -foreground [list disabled $colors(-disabledfg)]

        #
        # Layouts:
        #

        ttk::style layout TButton {
            Button.button -children {
                Button.focus -children {
                    Button.padding -children {
                        Button.label -side left -expand true
                    }
                }
            }
        }

        ttk::style layout Toolbutton {
            Toolbutton.button -children {
                Toolbutton.focus -children {
                    Toolbutton.padding -children {
                        Toolbutton.label -side left -expand true
                    }
                }
            }
        }

        ttk::style layout Vertical.TScrollbar {
            Vertical.Scrollbar.trough -sticky ns -children {
                Vertical.Scrollbar.thumb -expand true
            }
        }

        ttk::style layout Horizontal.TScrollbar {
            Horizontal.Scrollbar.trough -sticky ew -children {
                Horizontal.Scrollbar.thumb -expand true
            }
        }

        ttk::style layout TMenubutton {
            Menubutton.button -children {
                Menubutton.focus -children {
                    Menubutton.padding -children {
                        Menubutton.indicator -side right
                        Menubutton.label -side right -expand true
                    }
                }
            }
        }

        ttk::style layout TCombobox {
            Combobox.downarrow -side right -sticky ns -children {
                Combobox.arrow -side right
            }
            Combobox.field -side right -sticky nswe -expand 1 -children {
                Combobox.focus -children {
                    Combobox.padding -expand true -sticky nswe -children {
                        Combobox.textarea -side left -expand true
                    }
                }
            }
        }

        ttk::style layout TSpinbox {
            Spinbox.buttons -side right -sticky ns -children {
                null -side right -sticky ns -children {
                    Spinbox.uparrow -side top -sticky nse -children {
                        Spinbox.symuparrow -side right -sticky e
                    }
                    Spinbox.downarrow -side bottom -sticky nse -children {
                        Spinbox.symdownarrow -side right -sticky e
                    }
                }
            }
            Spinbox.field -side right -sticky nswe -expand 1 -children {
                Spinbox.padding -expand true -sticky nswe -children {
                    Spinbox.textarea -sticky nswe
                }
            }
        }

        #
        # Elements:
        #

        ttk::style element create Button.button image [list $I(button) \
                pressed     $I(button-active) \
                active      $I(button-hover) \
                disabled    $I(button-insensitive) \
            ] -border [s 3] -padding [s 3 2] -sticky nswe

        ttk::style element create Toolbutton.button image [list $I(button-empty) \
                selected            $I(button-active) \
                pressed             $I(button-active) \
                {active !disabled}  $I(button-hover) \
            ] -border [s 3] -padding [s 3 2] -sticky nswe

        ttk::style element create Checkbutton.indicator image [list $I(checkbox-unchecked) \
                disabled             $I(checkbox-unchecked-insensitive) \
                {active selected}    $I(checkbox-checked) \
                {pressed selected}   $I(checkbox-checked) \
                active               $I(checkbox-unchecked) \
                selected             $I(checkbox-checked) \
                {disabled selected}  $I(checkbox-checked-insensitive) \
                {active alternate}   $I(checkbox-tristate) \
                {pressed alternate}  $I(checkbox-tristate) \
                alternate            $I(checkbox-tristate) \
                {disabled alternate} $I(checkbox-tristate-insensitive) \
            ] -width [s 22] -sticky w

        ttk::style element create Radiobutton.indicator image [list $I(radio-unchecked) \
                disabled             $I(radio-unchecked-insensitive) \
                {active selected}    $I(radio-checked) \
                {pressed selected}   $I(radio-checked) \
                active               $I(radio-unchecked) \
                selected             $I(radio-checked) \
                {disabled selected}  $I(radio-checked-insensitive) \
                {active alternate}   $I(radio-tristate) \
                {pressed alternate}  $I(radio-tristate) \
                alternate            $I(radio-tristate) \
                {disabled alternate} $I(radio-tristate-insensitive) \
            ] -width [s 22] -sticky w

        ttk::style element create Horizontal.Scrollbar.trough image $I(trough-scrollbar-horiz)
        ttk::style element create Horizontal.Scrollbar.thumb \
            image [list $I(slider-horiz) \
                        {pressed !disabled} $I(slider-horiz-active) \
                        {active !disabled}  $I(slider-horiz-prelight) \
                        disabled            $I(slider-horiz-insens) \
            ] -border [s 6] -sticky ew

        ttk::style element create Vertical.Scrollbar.trough image $I(trough-scrollbar-vert)
        ttk::style element create Vertical.Scrollbar.thumb \
            image [list $I(slider-vert) \
                        {pressed !disabled} $I(slider-vert-active) \
                        {active !disabled}  $I(slider-vert-prelight) \
                        disabled            $I(slider-vert-insens) \
            ] -border [s 6] -sticky ns

        if {[package vsatisfies [package provide Tk] 9.1-]} {
            set grip grip
            set bw 0
        } else {
            set grip sash
            set bw 2
        }
        ttk::style element create h$grip image [list $I(handle-h) \
                        {active !disabled} $I(handle-h)] -border [s $bw $bw] \
                        -sticky {}
        ttk::style element create v$grip image [list $I(handle-v) \
                        {active !disabled} $I(handle-v)] -border [s $bw $bw] \
                        -sticky {}

        ttk::style element create Horizontal.Scale.trough \
            image [list $I(trough-horizontal-active) disabled $I(trough-horizontal)] \
            -border [s 8 5] -padding 0
        ttk::style element create Horizontal.Scale.slider \
            image [list $I(slider) disabled $I(slider-insensitive) active $I(slider-prelight)] \
            -sticky {}

        ttk::style element create Vertical.Scale.trough \
            image [list $I(trough-vertical-active) disabled $I(trough-vertical)] \
            -border [s 5 8] -padding 0
        ttk::style element create Vertical.Scale.slider \
            image [list $I(slider) disabled $I(slider-insensitive) active $I(slider-prelight)] \
            -sticky {}

        ttk::style element create Entry.field \
            image [list $I(entry-bg) \
                        focus $I(entry-active-bg) \
                        disabled $I(entry-disabled-bg) \
                        readonly $I(entry-readonly-bg) \
                        {readonly focus} $I(entry-readonly-active-bg)] \
            -border [s 3] -padding [s 6 4] -sticky news

        ttk::style element create Labelframe.border image $I(labelframe) \
            -border [s 4] -padding [s 4] -sticky news

        ttk::style element create Menubutton.button \
            image [list $I(button) \
                        pressed  $I(button-active) \
                        active   $I(button-hover) \
                        disabled $I(button-insensitive) \
            ] -sticky news -border [s 3] -padding [s 3 2]
        ttk::style element create Menubutton.indicator \
            image [list $I(arrow-down) \
                        active   $I(arrow-down-prelight) \
                        pressed  $I(arrow-down-prelight) \
                        disabled $I(arrow-down-insens) \
            ] -sticky e -width [s 20]

        ttk::style element create Combobox.field \
            image [list $I(combo-entry) \
                {readonly disabled}  $I(combo-entry-button-insensitive-rtl) \
                {readonly pressed}   $I(combo-entry-button-active-rtl) \
                {readonly hover}     $I(combo-entry-button-hover-rtl) \
                readonly             $I(combo-entry-button-rtl) \
                {disabled} $I(combo-entry-insensitive) \
                {focus}    $I(combo-entry-focus) \
            ] -border [s 3] -padding [s 3 2]
        ttk::style element create Combobox.downarrow \
            image [list $I(combo-entry-button) \
                        pressed   $I(combo-entry-button-active) \
                        active    $I(combo-entry-button-hover) \
                        disabled  $I(combo-entry-button-insensitive) \
            ] -border [s 3] -padding [s 0 10 8 10]
        ttk::style element create Combobox.arrow \
            image [list $I(arrow-down) \
                        active    $I(arrow-down-prelight) \
                        pressed   $I(arrow-down-prelight) \
                        disabled  $I(arrow-down-insens) \
            ] -sticky e -width [s 15]

        ttk::style element create Spinbox.field \
            image [list $I(combo-entry) \
                disabled $I(combo-entry-insensitive) \
                focus    $I(combo-entry-focus) \
                hover    $I(combo-entry) \
            ] -border [s 4] -padding [s 6 0 0 0] -sticky news
        ttk::style element create Spinbox.uparrow \
            image [list $I(up-background) \
                        pressed   $I(up-background-active) \
                        active    $I(up-background-hover) \
                        disabled  $I(up-background-disable) \
            ] -width [s 20] -border [s 0 2 3 0] -padding [s 0 5 6 2]
        ttk::style element create Spinbox.symuparrow \
            image [list $I(arrow-up-small) \
                        active    $I(arrow-up-small-prelight) \
                        pressed   $I(arrow-up-small-prelight) \
                        disabled  $I(arrow-up-small-insens) \
            ]
        ttk::style element create Spinbox.downarrow \
            image [list $I(down-background) \
                        pressed   $I(down-background-active) \
                        active    $I(down-background-hover) \
                        disabled  $I(down-background-disable) \
            ] -width [s 20] -border [s 0 0 3 2] -padding [s 0 2 6 5]
        ttk::style element create Spinbox.symdownarrow \
            image [list $I(arrow-down-small) \
                        active    $I(arrow-down-small-prelight) \
                        pressed   $I(arrow-down-small-prelight) \
                        disabled  $I(arrow-down-small-insens) \
          ]

        ttk::style element create Notebook.client \
            image $I(notebook) -border [s 1]
        ttk::style element create Notebook.tab \
            image [list $I(tab-top) \
                        selected    $I(tab-top-hover) \
                        active      $I(tab-top-hover) \
            ] -border [s 2] -padding [s 0 2 0 0]

        ttk::style element create Horizontal.Progressbar.trough \
            image $I(trough-progressbar_v) \
            -border [s 5 1] -padding [s 1] -sticky ew
        ttk::style element create Horizontal.Progressbar.pbar \
            image $I(progressbar_v) -border [s 4 0] -sticky ew

        ttk::style element create Vertical.Progressbar.trough \
            image $I(trough-progressbar) \
            -border [s 1 5] -padding [s 1] -sticky ns
        ttk::style element create Vertical.Progressbar.pbar \
            image $I(progressbar) -border [s 0 4] -sticky ns

        ttk::style element create Treeview.field \
            image $I(treeview) -border [s 1]
        ttk::style element create Treeheading.cell \
            image [list $I(notebook) pressed $I(notebook)] \
            -border [s 1] -padding [s 4] -sticky ewns

        if {![package vsatisfies [package provide Tk] 9-]} {
            ttk::style element create Treeitem.indicator \
                image [list $I(plus) user2 $I(empty) user1 $I(minus)] \
                -width [s 15] -sticky w
        } elseif {[package vsatisfies [package provide Tk] 9.1-]} {
            ttk::style element create Treeitem.indicator \
                image [list $I(plus) leaf $I(empty) open $I(minus)] \
                -width [s 15] -sticky w
        }

        #ttk::style element create Separator.separator image $I()

        #
        # Settings:
        #

        ttk::style configure TButton -padding [s 8 4] -width [s -5] -anchor center
        ttk::style configure TMenubutton -padding [s 8 4]
        ttk::style configure Toolbutton -anchor center -padding [s 4]
        ttk::style map TCheckbutton -background [list active $colors(-checklight)]
        ttk::style configure TCheckbutton -padding [s 3]
        ttk::style map TRadiobutton -background [list active $colors(-checklight)]
        ttk::style configure TRadiobutton -padding [s 3]
        ttk::style configure TEntry -insertwidth [s 1]
        ttk::style configure TCombobox -insertwidth [s 1] -padding [s 3 0]
        ttk::style map TCombobox -focuscolor [list {!readonly} $colors(-window)]
        ttk::style configure TSpinbox -insertwidth [s 1]
        ttk::style configure TNotebook -tabmargins [s 0 2 0 0]
        ttk::style configure TNotebook.Tab -padding [s 6 2] -expand [s 0 0 2]
        ttk::style map TNotebook.Tab -expand [list selected [s 1 2 4 2]]
        ttk::style configure TSeparator -background $colors(-bg)

        # Treeview
        ttk::style configure Treeview -background $colors(-window) -rowheight [s 20]
        ttk::style configure Treeview.Item -padding [s 2 0 0 0]
        ttk::style map Treeview \
            -background [list selected $colors(-selectbg)] \
            -foreground [list selected $colors(-selectfg)]

    }

    ttk::style theme create Arc -parent default -settings {
        ::ttk::theme::Arc::ThemeSettings colorsLight Arc
    }

    ttk::style theme create Arc-Dark -parent default -settings {
        ::ttk::theme::Arc::ThemeSettings colorsDark Arc-Dark
    }

    proc ConfigureColors {} {
        variable currentThemeForColors
        set theme [ttk::style theme use]

        # The <<ThemeChanged>> event is fired many times even if actually
        # theme is not changed, so ensure the options are set only once
        if {$theme eq $currentThemeForColors} {
            return
        } else {
            set currentThemeForColors $theme
        }

        if {$theme eq "Arc"} {
            variable colorsLight
            upvar 0 colorsLight colors
        } elseif {$theme eq "Arc-Dark"} {
            variable colorsDark
            upvar 0 colorsDark colors
        } else {
            return
        }

        #tk_setPalette \
        #    background $colors(-bg) \
        #    foreground $colors(-fg) \
        #    highlightColor $colors(-selectbg) \
        #    selectBackground $colors(-selectbg) \
        #    selectForeground $colors(-selectfg) \
        #    activeBackground $colors(-activebg) \
        #    activeForeground $colors(-activefg)

        # Main colors
        option add *background              $colors(-bg) widgetDefault
        option add *foreground              $colors(-fg) widgetDefault
        option add *readonlyBackground      $colors(-bg) widgetDefault
        option add *readonlyForeground      $colors(-fg) widgetDefault
        option add *disabledBackground      $colors(-disabledbg) widgetDefault
        option add *disabledForeground      $colors(-disabledfg) widgetDefault

        # Text widget
        option add *Text.background         $colors(-window) widgetDefault

        # Colors, which are used when mouse is over the item
        option add *activeBackground        $colors(-activebg) widgetDefault
        option add *activeForeground        $colors(-activefg) widgetDefault

        # Menu colors
        option add *Menu.activeBackground   $colors(-selectbg) widgetDefault
        option add *Menu.activeForeground   $colors(-selectfg) widgetDefault
        option add *Menu.borderWidth        [s 1] widgetDefault
        option add *Menu.borderColor        $colors(-disabledfg) widgetDefault
        option add *Menu.activeBorderWidth  0 widgetDefault
        option add *Menu.relief             raised widgetDefault

        # Colors and border width selected item
        option add *selectBackground        $colors(-selectbg) widgetDefault
        option add *selectForeground        $colors(-selectfg) widgetDefault
        option add *selectBorderWidth       0 widgetDefault

        # Color for checkboxes and radiobuttons
        option add *selectColor             $colors(-fg) widgetDefault

        # Insertion cursor
        option add *insertBackground        $colors(-fg) widgetDefault
        option add *insertWidth             [s 1] widgetDefault

        # Highlight rectangle
        option add *highlightBackground     $colors(-bg) widgetDefault
        option add *highlightColor          $colors(-selectbg) widgetDefault
        option add *Text.highlightThickness [s 1] widgetDefault
        option add *Canvas.highlightThickness [s 1] widgetDefault
    }

    proc ConfigureMenus {w} {
        if {[tk windowingsystem] in {aqua win32}} {
            return
        }

        variable currentThemeForMenus
        set theme [ttk::style theme use]
        # The <<ThemeChanged>> event is fired many times even if actually
        # theme is not changed, so ensure the menu colors are set only once
        # for a menu
        if {[info exists currentThemeForMenus($w)] && \
                $theme eq $currentThemeForMenus($w)} {
            return
        } else {
            set currentThemeForMenus($w) $theme
        }

        if {$theme eq "Arc"} {
            variable colorsLight
            upvar 0 colorsLight colors
        } elseif {$theme eq "Arc-Dark"} {
            variable colorsDark
            upvar 0 colorsDark colors
        } else {
            return
        }

        $w configure \
            -relief raised \
            -borderwidth [s 1] \
            -activeborderwidth 0 \
            -background $colors(-bg) \
            -foreground $colors(-fg) \
            -activebackground $colors(-selectbg) \
            -activeforeground $colors(-selectfg) \
            -selectcolor $colors(-fg)

        if {![catch {[winfo toplevel $w] cget -menu}]} {
            if {[[winfo toplevel $w] cget -menu] != $w} {
                $w configure \
                    -relief raised \
                    -borderwidth [s 1] \
                    -background $colors(-bg) \
                    -foreground $colors(-fg) \
                    -activebackground $colors(-selectbg) \
                    -activeforeground $colors(-selectfg) \
                    -selectcolor $colors(-fg)
            }
        }
    }

    bind [winfo class .] <<ThemeChanged>> +[namespace code ConfigureColors]
    bind Menu <<ThemeChanged>> +[namespace code [list ConfigureMenus %W]]
}

# vim:ts=8:sw=4:sts=4:et
