# tConfClass.tcl - Configuration class using Tcl 9's oo::configurable
package require Tcl 9.0

# Create the configurable class
oo::configurable create ::Config {
    # Define properties (variables will be created automatically)
    property backend filename
    property data -kind readable -get {
        return [dict create {*}$data]
    }

    # Declare variables (after properties, as in the example)
    variable backend
    variable filename
    variable data

    constructor {args} {
        # Initialize data
        set data [dict create]
        # Configure with provided arguments
        my configure -backend "" -filename "" {*}$args
    }

    # Set a configuration value
    method set {key value} {
        dict set data $key $value
        return
    }

    # Get a configuration value
    method get {key {default ""}} {
        if {[dict exists $data $key]} {
            return [dict get $data $key]
        }
        return $default
    }

    # Check if key exists
    method exists {key} {
        return [dict exists $data $key]
    }

    # Unset a key
    method unset {key} {
        if {[dict exists $data $key]} {
            dict unset data $key
            return 1
        }
        return 0
    }

    # Get all data
    method getAll {} {
        return $data
    }

    # Save using backend
    method save {{file ""}} {
        if {$backend eq ""} {
            error "No backend selected"
        }
        set saveFile [expr {$file ne "" ? $file : $filename}]
        if {$saveFile eq ""} {
            error "No filename specified"
        }
        $backend save $saveFile $data
        return
    }

    # Load using backend
    method load {{file ""}} {
        if {$backend eq ""} {
            error "No backend selected"
        }
        set loadFile [expr {$file ne "" ? $file : $filename}]
        if {$loadFile eq ""} {
            error "No filename specified"
        }
        set data [$backend load $loadFile]
        return
    }

    # Set backend
    method useBackend {backendObj {file ""}} {
        set backend $backendObj
        if {$file ne ""} {
            set filename $file
        }
        return
    }
}

package provide tConfClass 1.0
return
