# backends/yaml.tcl - YAML Backend for Configuration Class

# YAML Backend
::oo::class create ::Config::Backend::Yaml {
    variable opts

    constructor {{options {}}} {
        set opts $options

        # Check for yaml package
        if {[catch {package require yaml}]} {
            # Try to load fallback yaml parser
            if {[catch {package require yaml::core}]} {
                error "YAML package not available (tcllib required)"
            }
        }
    }

    method load {file} {
        if {![file exists $file]} {
            return [dict create]
        }

        set fp [open $file r]
        set data [read $fp]
        close $fp

        # Handle different yaml package versions
        if {[info commands ::yaml::yaml2dict] ne ""} {
            return [::yaml::yaml2dict $data]
        } elseif {[info commands ::yaml::decode] ne ""} {
            return [::yaml::decode $data]
        } else {
            error "YAML parser not available"
        }
    }

    method save {file data} {
        # Handle different yaml package versions
        if {[info commands ::yaml::dict2yaml] ne ""} {
            set yaml [::yaml::dict2yaml $data]
        } elseif {[info commands ::yaml::encode] ne ""} {
            set yaml [::yaml::encode $data]
        } else {
            error "YAML serializer not available"
        }

        set fp [open $file w]
        puts $fp $yaml
        close $fp
        return
    }
}

# Register the backend
::Config::registerBackend yaml {
    ::Config::Backend::Yaml
}

return
