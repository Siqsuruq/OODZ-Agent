package require Thread 3.0

::oo::class create tPluginWorker {
    variable threadId requestCounter syncCounter asyncVariables shuttingDown

    constructor {
        scriptDir workspaceRoot pluginDirectories executionTimeout maxOutput
        {referenceRoots {}} {runnerConfig {}} {configuredPlatform ""}
    } {
        set threadId ""
        set requestCounter 0
        set syncCounter 0
        set asyncVariables [dict create]
        set shuttingDown 0

        set bootstrap {
            package require Thread 3.0

            namespace eval ::PluginWorkerThread {
                variable registry ""
                variable runner ""

                proc approve {name arguments} {
                    # The main-thread registry validates arguments and obtains
                    # approval before dispatching write tools here.
                    return 1
                }

                proc initialize {
                    scriptDir workspaceRoot pluginDirectories executionTimeout
                    maxOutput referenceRoots runnerConfig configuredPlatform
                } {
                    variable registry
                    variable runner

                    lappend ::auto_path [file join $scriptDir lib]
                    uplevel #0 [list source \
                        [file join $scriptDir processRunner.tcl]]
                    uplevel #0 [list source \
                        [file join $scriptDir pluginRegistry.tcl]]

                    set runner ""
                    if {[dict exists $runnerConfig enabled]
                            && [dict get $runnerConfig enabled]} {
                        set runner [tProcessRunner new \
                            $workspaceRoot \
                            [dict get $runnerConfig tclsh] \
                            [dict get $runnerConfig timeout_ms] \
                            [dict get $runnerConfig max_output_chars] \
                            "" \
                            [dict get $runnerConfig executable_aliases]]
                        if {[dict exists $runnerConfig project_tests_enabled]
                                && [dict get $runnerConfig \
                                    project_tests_enabled]} {
                            $runner configureProjectTests \
                                [dict get $runnerConfig \
                                    project_tests_executable] \
                                [dict get $runnerConfig \
                                    project_tests_arguments] \
                                [dict get $runnerConfig \
                                    project_tests_timeout_ms]
                        }
                    }

                    set registry [tPluginRegistry new \
                        $workspaceRoot $pluginDirectories \
                        ::PluginWorkerThread::approve \
                        $executionTimeout $maxOutput $referenceRoots \
                        "" "" $runner false {} $configuredPlatform]
                    return
                }

                proc invokeEnvelope {name argumentsJson} {
                    variable registry
                    if {[catch {
                        $registry invoke $name $argumentsJson
                    } result options]} {
                        set envelope [dict create status error message $result]
                        if {[dict exists $options -errorcode]} {
                            dict set envelope errorcode \
                                [dict get $options -errorcode]
                        }
                        return $envelope
                    }
                    return [dict create status ok result $result]
                }

                proc shutdown {} {
                    variable registry
                    variable runner
                    if {$registry ne ""
                            && [info object isa object $registry]} {
                        $registry destroy
                    }
                    if {$runner ne "" && [info object isa object $runner]} {
                        $runner destroy
                    }
                    set registry ""
                    set runner ""
                    return
                }
            }

            thread::wait
        }

        set threadId [thread::create $bootstrap]
        if {[catch {
            thread::send $threadId [list \
                ::PluginWorkerThread::initialize \
                $scriptDir $workspaceRoot $pluginDirectories \
                $executionTimeout $maxOutput $referenceRoots \
                $runnerConfig $configuredPlatform]
        } message options]} {
            catch {thread::release $threadId}
            set threadId ""
            return -options $options $message
        }
    }

    destructor {
        set shuttingDown 1
        dict for {requestId request} $asyncVariables {
            set variableName [dict get $request variable]
            set callback [dict get $request callback]
            catch {trace remove variable $variableName write \
                [list [self] completeAsync $requestId $callback $variableName]}
            catch {unset $variableName}
        }
        set asyncVariables [dict create]
        if {$threadId ne "" && [thread::exists $threadId]} {
            catch {thread::send $threadId ::PluginWorkerThread::shutdown}
            catch {thread::release $threadId}
        }
        set threadId ""
    }

    method invoke {name argumentsJson} {
        if {$shuttingDown || $threadId eq ""
                || ![thread::exists $threadId]} {
            error "Plugin worker is not running"
        }
        set token [incr syncCounter]
        set objectNamespace [info object namespace [self]]
        set doneVariable "${objectNamespace}::sync_done_$token"
        set resultVariable "${objectNamespace}::sync_result_$token"
        set $doneVariable 0
        my invokeAsync $name $argumentsJson \
            [list [self] completeSync $doneVariable $resultVariable]
        vwait $doneVariable
        set envelope [set $resultVariable]
        unset $doneVariable $resultVariable
        return [my decodeEnvelope $envelope]
    }

    method completeSync {doneVariable resultVariable requestId envelope} {
        set $resultVariable $envelope
        set $doneVariable 1
        return
    }

    method invokeAsync {name argumentsJson callback} {
        if {$shuttingDown || $threadId eq ""
                || ![thread::exists $threadId]} {
            error "Plugin worker is not running"
        }
        if {[llength $callback] == 0} {
            error "Plugin worker callback must not be empty"
        }
        set requestId [incr requestCounter]
        set variableName "[info object namespace [self]]::async_$requestId"
        dict set asyncVariables $requestId [dict create \
            variable $variableName callback $callback]
        trace add variable $variableName write \
            [list [self] completeAsync $requestId $callback $variableName]
        thread::send -async $threadId [list \
            ::PluginWorkerThread::invokeEnvelope $name $argumentsJson] \
            $variableName
        return $requestId
    }

    method completeAsync {requestId callback variableName args} {
        if {![dict exists $asyncVariables $requestId]} {
            return
        }
        trace remove variable $variableName write \
            [list [self] completeAsync $requestId $callback $variableName]
        set envelope [set $variableName]
        unset $variableName
        dict unset asyncVariables $requestId
        if {!$shuttingDown} {
            after 0 [list {*}$callback $requestId $envelope]
        }
        return
    }

    method decodeEnvelope {envelope} {
        if {[dict get $envelope status] eq "ok"} {
            return [dict get $envelope result]
        }
        set message [dict get $envelope message]
        if {[dict exists $envelope errorcode]} {
            return -code error -errorcode \
                [dict get $envelope errorcode] $message
        }
        error $message
    }

    method busy {} {
        expr {[dict size $asyncVariables] > 0}
    }

    method threadId {} {
        return $threadId
    }
}
