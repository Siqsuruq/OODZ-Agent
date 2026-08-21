::oo::class create tLogger {
    variable loggerName
    variable currentLevel
    variable levelMap
    variable appenders 
    set [info object namespace [self]]::registry() ""
    set [info object namespace [self]]::appenderFactory \
        [list ::ConsoleAppender new]
    constructor {name} {
        set loggerName $name
        set currentLevel 1 ;# Default to 'info'
        set appenders [list] 
        dict set levelMap debug 0
        dict set levelMap info 1
        dict set levelMap warn 2
        dict set levelMap error 3
        dict set levelMap critical 4
        namespace upvar [info object namespace [self class]] \
            appenderFactory appenderFactory
        my addAppender [{*}$appenderFactory]
    }

    classmethod getLogger {args} {
        set currentClass [self]
        set name [expr {[llength $args] > 0 ? [lindex $args 0] : "Global"}]
        namespace upvar [info object namespace $currentClass] registry registry
        if {[info exists registry($name)] && [info object isa object $registry($name)]} {
            return $registry($name)
        }
        set instance [$currentClass new $name]
        set registry($name) $instance
        return $instance
    }

    classmethod setAppenderFactory {factory} {
        set currentClass [self]
        namespace upvar [info object namespace $currentClass] \
            registry registry appenderFactory appenderFactory
        set appenderFactory $factory
        foreach name [array names registry] {
            set logger $registry($name)
            if {[info object isa object $logger]} {
                $logger replaceAppender $factory
            }
        }
    }

    # API Method allowing external custom appenders to link in seamlessly
    method addAppender {appenderObject} {
        # FIX: Enterprise Type Guard using native 'typeof' validation
        if {![info object isa object $appenderObject] || ![info object isa typeof $appenderObject ::tAppender]} {
            error "Invalid Appender! Handlers must inherit from the abstract 'tAppender' base class."
        }
        lappend appenders $appenderObject
    }

    method replaceAppender {factory} {
        foreach appender $appenders {
            if {[info object isa object $appender]} {
                $appender destroy
            }
        }
        set appenders [list]
        my addAppender [{*}$factory]
    }

    method setLogLevel {level} {
        set level [string tolower $level]
        if {[dict exists $levelMap $level]} {
            set currentLevel [dict get $levelMap $level]
        }
    }

    method log {level message} {
        set level [string tolower $level]
        if {![dict exists $levelMap $level]} { return }
        if {[dict get $levelMap $level] < $currentLevel} { return }
        set callerContext "global"
        if {[catch {uplevel 1 {self method}} ooMethod] == 0 && $ooMethod ne ""} {
            set callerContext $ooMethod
        } elseif {[info level] > 1} {
            set callerCmd [lindex [info level -1] 0]
            if {$callerCmd ne ""} { set callerContext $callerCmd }
        }
        set timestamp [clock format [clock seconds] -format "%Y-%m-%dT%H:%M:%S"]
        # Broadcast engine stays clean
        foreach appender $appenders {
            if {[info object isa object $appender]} {
                $appender append $timestamp $loggerName $callerContext $level $message
            }
        }
    }
}

package provide tLogger 1.0.0
