namespace eval ::oodzMarkdownTk {
    variable streams [dict create]
}

proc ::oodzMarkdownTk::mergeSpan {spans text tags} {
    if {$text eq ""} {
        return $spans
    }
    if {[llength $spans] > 0
            && [lindex [lindex $spans end] 1] eq $tags} {
        set previous [lindex $spans end]
        lset spans end [list "[lindex $previous 0]$text" $tags]
    } else {
        lappend spans [list $text $tags]
    }
    return $spans
}

proc ::oodzMarkdownTk::inline {text baseTags} {
    set spans {}
    set plain ""
    set length [string length $text]
    for {set index 0} {$index < $length} {} {
        set rest [string range $text $index end]
        set consumed 0
        foreach {pattern tag prefix suffix} {
            {^`([^`]+)`} mdInlineCode ` `
            {^\*\*([^*]+)\*\*} mdBold ** **
            {^__([^_]+)__} mdBold __ __
            {^\[([^]]+)\]\(([^)]+)\)} mdLink {} {}
            {^\*([^*]+)\*} mdItalic * *
            {^_([^_]+)_} mdItalic _ _
        } {
            if {![regexp -indices $pattern $rest match first second]} {
                continue
            }
            if {$plain ne ""} {
                set spans [::oodzMarkdownTk::mergeSpan \
                    $spans $plain $baseTags]
                set plain ""
            }
            lassign $first firstStart firstEnd
            set value [string range $rest $firstStart $firstEnd]
            if {$tag eq "mdLink"} {
                lassign $second secondStart secondEnd
                set target [string range $rest $secondStart $secondEnd]
                set value "$value ($target)"
            }
            set spans [::oodzMarkdownTk::mergeSpan \
                $spans $value [list {*}$baseTags $tag]]
            lassign $match matchStart matchEnd
            set consumed [expr {$matchEnd + 1}]
            break
        }
        if {$consumed > 0} {
            incr index $consumed
        } else {
            ::append plain [string index $text $index]
            incr index
        }
    }
    if {$plain ne ""} {
        set spans [::oodzMarkdownTk::mergeSpan $spans $plain $baseTags]
    }
    return $spans
}

proc ::oodzMarkdownTk::parseLine {state line {baseTag assistant}} {
    set inFence [dict get $state in_fence]
    if {[regexp {^[[:space:]]*```([^[:space:]`]*)[[:space:]]*$} \
            $line -> language]} {
        dict set state in_fence [expr {!$inFence}]
        set spans {}
        if {!$inFence && $language ne ""} {
            lappend spans [list "$language\n" \
                [list $baseTag mdCodeLanguage]]
        }
        return [list $state $spans]
    }
    if {$inFence} {
        return [list $state [list [list "$line\n" \
            [list $baseTag mdCodeBlock]]]]
    }
    if {$line eq ""} {
        return [list $state [list [list "\n" [list $baseTag]]]]
    }
    if {[regexp {^(#{1,6})[[:space:]]+(.+)$} $line -> marks content]} {
        set level [string length $marks]
        set spans [::oodzMarkdownTk::inline $content \
            [list $baseTag mdHeading mdH$level]]
        lappend spans [list "\n" [list $baseTag mdH$level]]
        return [list $state $spans]
    }
    if {[regexp {^[[:space:]]*([-*_])[[:space:]]*\1[[:space:]]*\1([[:space:]]*\1)*[[:space:]]*$} $line]} {
        return [list $state [list [list "────────────────\n" \
            [list $baseTag mdRule]]]]
    }
    if {[regexp {^[[:space:]]*[-+*][[:space:]]+(.+)$} $line -> content]} {
        set spans [list [list "• " [list $baseTag mdList]]]
        set spans [concat $spans [::oodzMarkdownTk::inline \
            $content [list $baseTag mdList]]]
        lappend spans [list "\n" [list $baseTag mdList]]
        return [list $state $spans]
    }
    if {[regexp {^[[:space:]]*([0-9]+)[.)][[:space:]]+(.+)$} \
            $line -> number content]} {
        set spans [list [list "$number. " [list $baseTag mdList]]]
        set spans [concat $spans [::oodzMarkdownTk::inline \
            $content [list $baseTag mdList]]]
        lappend spans [list "\n" [list $baseTag mdList]]
        return [list $state $spans]
    }
    if {[regexp {^[[:space:]]*>[[:space:]]?(.*)$} $line -> content]} {
        set spans [::oodzMarkdownTk::inline $content \
            [list $baseTag mdQuote]]
        lappend spans [list "\n" [list $baseTag mdQuote]]
        return [list $state $spans]
    }
    set spans [::oodzMarkdownTk::inline $line [list $baseTag]]
    lappend spans [list "\n" [list $baseTag]]
    return [list $state $spans]
}

proc ::oodzMarkdownTk::insertSpans {widget spans} {
    foreach span $spans {
        lassign $span text tags
        $widget insert end $text $tags
    }
}

proc ::oodzMarkdownTk::withWritable {widget script} {
    set previous [$widget cget -state]
    if {$previous eq "disabled"} {
        $widget configure -state normal
    }
    try {
        uplevel 1 $script
    } finally {
        if {$previous eq "disabled"} {
            $widget configure -state disabled
        }
    }
}

proc ::oodzMarkdownTk::attach {widget} {
    if {![winfo exists $widget]} {
        error "Markdown target widget does not exist: $widget"
    }
    foreach {name base options} {
        oodzMarkdownTkBold TkTextFont {-weight bold}
        oodzMarkdownTkItalic TkTextFont {-slant italic}
        oodzMarkdownTkH1 TkHeadingFont {-size 18 -weight bold}
        oodzMarkdownTkH2 TkHeadingFont {-size 16 -weight bold}
        oodzMarkdownTkH3 TkHeadingFont {-size 14 -weight bold}
    } {
        if {$name ni [font names]} {
            font create $name {*}[font actual $base] {*}$options
        }
    }
    $widget tag configure mdBold -font oodzMarkdownTkBold
    $widget tag configure mdItalic -font oodzMarkdownTkItalic
    $widget tag configure mdInlineCode -font TkFixedFont \
        -background #30343f -foreground #f3c969
    $widget tag configure mdCodeBlock -font TkFixedFont \
        -background #252934 -foreground #d8dee9 \
        -lmargin1 16 -lmargin2 16 -rmargin 16
    $widget tag configure mdCodeLanguage -font TkSmallCaptionFont \
        -foreground #aab2c0 -lmargin1 16
    $widget tag configure mdHeading -font TkHeadingFont \
        -spacing1 8 -spacing3 4
    $widget tag configure mdH1 -font oodzMarkdownTkH1
    $widget tag configure mdH2 -font oodzMarkdownTkH2
    $widget tag configure mdH3 -font oodzMarkdownTkH3
    $widget tag configure mdList -lmargin1 20 -lmargin2 36
    $widget tag configure mdQuote -lmargin1 20 -lmargin2 20 \
        -foreground #aab2c0
    $widget tag configure mdRule -foreground #697180
    $widget tag configure mdLink -foreground #6cb6ff -underline 1
    return $widget
}

proc ::oodzMarkdownTk::begin {widget {baseTag assistant}} {
    variable streams
    if {[dict exists $streams $widget]} {
        error "Markdown stream is already active for widget: $widget"
    }
    dict set streams $widget [dict create \
        buffer "" in_fence 0 base_tag $baseTag tentative_start [$widget index end]]
    return
}

proc ::oodzMarkdownTk::append {widget chunk} {
    variable streams
    if {![dict exists $streams $widget]} {
        error "Markdown stream is not active for widget: $widget"
    }
    set stream [dict get $streams $widget]
    dict append stream buffer $chunk
    set tentativeStart [dict get $stream tentative_start]
    ::oodzMarkdownTk::withWritable $widget [list $widget delete $tentativeStart end]

    set buffer [dict get $stream buffer]
    set state [dict create in_fence [dict get $stream in_fence]]
    set baseTag [dict get $stream base_tag]
    set committedSpans {}
    while {[set newline [string first "\n" $buffer]] >= 0} {
        set line [string range $buffer 0 [expr {$newline - 1}]]
        set buffer [string range $buffer [expr {$newline + 1}] end]
        lassign [::oodzMarkdownTk::parseLine $state $line $baseTag] \
            state spans
        set committedSpans [concat $committedSpans $spans]
    }
    ::oodzMarkdownTk::withWritable $widget {
        ::oodzMarkdownTk::insertSpans $widget $committedSpans
    }
    dict set stream in_fence [dict get $state in_fence]
    dict set stream buffer $buffer
    dict set stream tentative_start [$widget index end]
    if {$buffer ne ""} {
        set previewState $state
        lassign [::oodzMarkdownTk::parseLine \
            $previewState $buffer $baseTag] ignored previewSpans
        # A tentative line has no committed newline yet.
        if {[llength $previewSpans] > 0
                && [lindex [lindex $previewSpans end] 0] eq "\n"} {
            set previewSpans [lrange $previewSpans 0 end-1]
        }
        ::oodzMarkdownTk::withWritable $widget {
            ::oodzMarkdownTk::insertSpans $widget $previewSpans
        }
    }
    dict set streams $widget $stream
    $widget see end
    return
}

proc ::oodzMarkdownTk::finish {widget} {
    variable streams
    if {![dict exists $streams $widget]} {
        return
    }
    set stream [dict get $streams $widget]
    set buffer [dict get $stream buffer]
    set tentativeStart [dict get $stream tentative_start]
    ::oodzMarkdownTk::withWritable $widget [list $widget delete $tentativeStart end]
    if {$buffer ne ""} {
        set state [dict create in_fence [dict get $stream in_fence]]
        lassign [::oodzMarkdownTk::parseLine $state $buffer \
            [dict get $stream base_tag]] ignored spans
        ::oodzMarkdownTk::withWritable $widget {
            ::oodzMarkdownTk::insertSpans $widget $spans
        }
    }
    dict unset streams $widget
    $widget see end
    return
}

proc ::oodzMarkdownTk::render {widget text {baseTag assistant}} {
    ::oodzMarkdownTk::begin $widget $baseTag
    ::oodzMarkdownTk::append $widget $text
    ::oodzMarkdownTk::finish $widget
}

package provide oodzMarkdownTk 0.1.0
