# backends/json.tcl - JSON Backend for Configuration Class

# JSON Backend
::oo::class create ::Config::Backend::Json {
    variable opts

    constructor {{options {}}} {
        set opts $options
    }

    method load {file} {
        if {![file exists $file]} {
            return [dict create]
        }

        set fp [open $file r]
        set data [read $fp]
        close $fp

        # Use Tcllib json if available
        if {[catch {package require json}]} {
            # Fallback to simple parsing
            return [my parseSimpleJson $data]
        } else {
            return [json::json2dict $data]
        }
    }

    method save {file data} {
        if {[catch {package require json}]} {
            set json [my dictToSimpleJson $data]
        } else {
            set json [json::dict2json $data]
        }

        set fp [open $file w]
        puts $fp $json
        close $fp
        return
    }

    # Simple JSON parser (limited functionality - for demo only)
    method parseSimpleJson {text} {
        # Remove whitespace and braces
        set text [string trim $text]
        if {[string index $text 0] eq "{"} {
            set text [string range $text 1 end-1]
        }

        set result [dict create]
        set pairs [split $text ,]

        foreach pair $pairs {
            if {[regexp {^"([^"]+)"\s*:\s*"(.*)"$} $pair -> key value]} {
                dict set result $key $value
            }
        }

        return $result
    }

    method dictToSimpleJson {dictData} {
        set parts {}
        dict for {key value} $dictData {
            lappend parts "\"$key\": \"$value\""
        }
        return "{[join $parts ,]}"
    }
}

# Register the backend
::Config::registerBackend json {
    ::Config::Backend::Json
}

return
