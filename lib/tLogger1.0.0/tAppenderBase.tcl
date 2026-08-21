if {[info commands ::tAppender] eq ""} {
    oo::abstract create tAppender {
        method append {timestamp loggerName context level message} {
            error "Abstract Method Error: 'append' must be overridden by a subclass!"
        }
    }
}

package provide tLogger 1.0.0