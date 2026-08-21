# backends/ini.tcl - INI Backend using tcllib's inifile package
package require Tcl 9.0
package require inifile

::oo::class create ::Config::Backend::Ini {
    method load {file} {
        if {![file exists $file]} {
            return [dict create]
        }

        # Open the INI file for reading
        set ini [::ini::open $file r]
        set result [dict create]

        # Get all sections
        set sections [::ini::sections $ini]

        # If there are no sections, treat as default section
        if {$sections eq ""} {
            # Get all keys from the default section
            set keys [::ini::keys $ini ""]
            foreach key $keys {
                set value [::ini::value $ini "" $key]
                dict set result $key $value
            }
        } else {
            # Process each section
            foreach section $sections {
                set keys [::ini::keys $ini $section]
                foreach key $keys {
                    set value [::ini::value $ini $section $key]
                    set fullKey "${section}.${key}"
                    dict set result $fullKey $value
                }
            }
        }

        ::ini::close $ini
        return $result
    }

    method save {file data} {
        # Create a new INI file for writing
        set ini [::ini::open $file w]

        # Group data by sections
        set sections [dict create]
        set globalKeys [dict create]

        dict for {key value} $data {
            if {[regexp {^([^\.]+)\.(.+)$} $key -> section name]} {
                dict set sections $section $name $value
            } else {
                dict set globalKeys $key $value
            }
        }

        # Write global keys (in default section)
        dict for {key value} $globalKeys {
            ::ini::set $ini "" $key $value
        }

        # Write sections
        dict for {section keys} $sections {
            dict for {name value} $keys {
                ::ini::set $ini $section $name $value
            }
        }

        ::ini::commit $ini
        ::ini::close $ini
        return
    }
}

return
