if {[info commands ::ConsoleAppender] eq ""} {
    oo::class create ConsoleAppender {
        superclass tAppender
        method append {timestamp loggerName context level message} {
            puts stderr "\[$timestamp\] \[$loggerName\] \[$context\] \[[string toupper $level]\] $message"
            flush stderr
        }
    }
}

if {[info commands ::FileAppender] eq ""} {
    oo::class create FileAppender {
        superclass tAppender
        variable fileChannel
        constructor {filePath} {
            set fileChannel [open $filePath a]
            fconfigure $fileChannel -encoding utf-8 -buffering line
        }
        destructor {
            if {[info exists fileChannel]} { close $fileChannel }
        }
        method append {timestamp loggerName context level message} {
            puts $fileChannel "\[$timestamp\] \[$loggerName\] \[$context\] \[[string toupper $level]\] $message"
        }
    }
}

package provide tLogger 1.0.0
