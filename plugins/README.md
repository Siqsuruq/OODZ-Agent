# Tool plugins

Each direct child directory is one tool plugin:

```text
plugins/
  example_tool/
    plugin.ini
    plugin.tcl
```

Personal plugin roots can be kept outside the repository and enabled in
`conf/conf.ini`:

```ini
[Plugins]
directories = /home/max/.oodz/plugins
```

Multiple roots are comma-separated. Relative paths resolve from the agent
installation directory. Every configured root must already exist. The built-in
`plugins/` root is always loaded first, and duplicate tool names are rejected.

## Manifest

`plugin.ini` declares the model-visible contract:

```ini
[plugin]
name = example_tool
description = Explain clearly when the model should use this tool.
permission = read
entrypoint = plugin.tcl
handler = ::plugins::example_tool::execute
parameters = {"type":"object","properties":{"value":{"type":"string"}},"required":["value"],"additionalProperties":false}
```

Rules:

- `name` must match `[a-z][a-z0-9_]*` and must be unique.
- `permission` is currently `read` or `write`.
- `entrypoint` must be a filename inside the plugin directory.
- `handler` must name a Tcl command created by the entrypoint.
- `parameters` must be a JSON object schema.

## Handler

The handler receives the normalized workspace root, validated model arguments,
and private plugin settings:

```tcl
namespace eval ::plugins::example_tool {}

proc ::plugins::example_tool::execute {
    workspaceRoot arguments settings
} {
    set value [dict get $arguments value]
    return "Received: $value"
}
```

Return a string that can be sent back to the model as the tool result. Raise a
normal Tcl error when the tool cannot complete.

The optional `[settings]` section contains trusted plugin-owned configuration:

```ini
[settings]
base_url = http://127.0.0.1:8080
timeout_ms = 10000
```

Settings are loaded during discovery and passed as a dictionary. If the section
is absent, the handler receives an empty dictionary. Settings are never included
in model-visible tool definitions or logged automatically. Do not return secrets
from a handler because tool results are sent to the model.

For filesystem access, resolve user-provided relative paths with:

```tcl
set path [::PluginSupport::resolveWorkspacePath \
    $workspaceRoot [dict get $arguments path]]
```

This rejects absolute paths and paths that escape the workspace.

## Trust boundary

Plugin argument schemas protect the tool interface presented to the model, but a
plugin's Tcl implementation is executable local code. Install only plugins you
trust. Plugins run with the same operating-system privileges as the agent.

Do not create plugins that expose unrestricted `exec`, `eval`, or arbitrary Tcl
scripts. Mutating plugins will require an approval boundary before they are
enabled in the agent loop.

Handlers run in a dedicated Tcl interpreter with a per-call execution deadline
and output-size limit. These limits constrain Tcl execution and returned data;
they do not make untrusted plugin code safe.

Plugins marked `permission = write` require the registry host to provide an
approval callback. The standard CLI asks for confirmation before each write.
Read-only plugins execute without approval.
