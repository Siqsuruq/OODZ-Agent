#!/usr/bin/env tclsh

# Set up paths
lappend auto_path [file dirname [info script]]

# Load the package
package require tConfClass

# Load INI backend (uses inifile package)
source [file join [file dirname [info script]] backends ini.tcl]

# Create config object
set config [::Config new]

# Create backend
set iniBackend [::Config::Backend::Ini new]

# Use the backend
$config useBackend $iniBackend "test.ini"

# Set values
$config set "database.host" "localhost"
$config set "database.port" 5432
$config set "database.user" "admin"
$config set "app.name" "MyApp"
$config set "app.debug" true
$config set "app.version" "1.0.0"

# Test get
puts "=== Testing get ==="
puts "Host: [$config get database.host]"
puts "Port: [$config get database.port]"
puts "User: [$config get database.user]"
puts "Name: [$config get app.name]"
puts "Debug: [$config get app.debug]"

# Test configure
puts "\n=== Testing configure ==="
puts "Backend: [$config configure -backend]"
puts "Filename: [$config configure -filename]"

# Save
puts "\n=== Saving to test.ini ==="
$config save
puts "Saved successfully!"

# Load into new config
puts "\n=== Loading from test.ini ==="
set config2 [::Config new]
$config2 useBackend $iniBackend "test.ini"
$config2 load

puts "Loaded data:"
dict for {key value} [$config2 getAll] {
    puts "  $key = $value"
}

# Test modifying and saving
puts "\n=== Modifying and saving ==="
$config2 set "app.version" "2.0.0"
$config2 set "database.port" 5433
$config2 save
puts "Updated and saved!"

# Test loading the updated file
puts "\n=== Loading updated file ==="
set config3 [::Config new]
$config3 useBackend $iniBackend "test.ini"
$config3 load

puts "Updated data:"
dict for {key value} [$config3 getAll] {
    puts "  $key = $value"
}

puts "\n=== Test complete ==="
