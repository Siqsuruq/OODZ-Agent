# backends/sqlite.tcl - SQLite Backend for Configuration Class

# SQLite Backend
::oo::class create ::Config::Backend::Sqlite {
    variable opts
    variable db

    constructor {{options {}}} {
        set opts $options
        set db ""

        if {[catch {package require sqlite3}]} {
            error "SQLite package not available"
        }

        if {[dict exists $options -database]} {
            set dbFile [dict get $options -database]
            sqlite3 db $dbFile
            set db $db
            my initSchema
        }
    }

    method initSchema {} {
        variable db
        if {$db ne ""} {
            $db eval {
                CREATE TABLE IF NOT EXISTS config (
                    key TEXT PRIMARY KEY,
                    value TEXT
                )
            }

            $db eval {
                CREATE INDEX IF NOT EXISTS idx_config_key ON config(key)
            }
        }
    }

    method load {file} {
        variable db
        variable opts

        if {$db eq ""} {
            # Open database
            set dbFile [dict get $opts -database]
            if {$dbFile eq ""} {
                set dbFile $file
            }
            sqlite3 db $dbFile
            set db $db
            my initSchema
        }

        set result [dict create]
        $db eval {SELECT key, value FROM config ORDER BY key} {
            dict set result $key $value
        }

        return $result
    }

    method save {file data} {
        variable db
        variable opts

        if {$db eq ""} {
            set dbFile [dict get $opts -database]
            if {$dbFile eq ""} {
                set dbFile $file
            }
            sqlite3 db $dbFile
            set db $db
            my initSchema
        }

        # Begin transaction
        $db eval {BEGIN TRANSACTION}

        # Clear existing data
        $db eval {DELETE FROM config}

        # Insert new data
        dict for {key value} $data {
            $db eval {INSERT INTO config (key, value) VALUES ($key, $value)}
        }

        $db eval {COMMIT}
        return
    }

    # Additional utility methods
    method getValue {key} {
        variable db
        if {$db eq ""} { return "" }

        set result [$db eval {SELECT value FROM config WHERE key = $key}]
        if {[llength $result] > 0} {
            return [lindex $result 0]
        }
        return ""
    }

    method deleteKey {key} {
        variable db
        if {$db eq ""} { return }

        $db eval {DELETE FROM config WHERE key = $key}
        return
    }

    method getAllKeys {} {
        variable db
        if {$db eq ""} { return {} }

        return [$db eval {SELECT key FROM config ORDER BY key}]
    }
}

# Register the backend
::Config::registerBackend sqlite {
    ::Config::Backend::Sqlite
}

return
