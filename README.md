# OODZ Agent

OODZ Agent is a small Tcl coding agent for supported OpenAI-compatible
chat-completions APIs. DeepSeek and local Ollama models can request registered
tool plugins, receive their results, and continue until producing a final answer.

The multi-page HTML documentation starts at
[`docs/index.html`](docs/index.html). Pico CSS 2.1.1 and the OODZ stylesheet are
stored locally under `docs/`, so the documentation works offline without
JavaScript.

## Requirements

- Tcl 9.0 or newer
- Tcl Thread package 3.0 or newer
- Tcl TLS package (`tls`)
- Tcllib packages:
  - `http`
  - `json`
  - `json::write`
  - `fileutil`

The repository includes its INI configuration, logging, and Zesty terminal
packages. No additional package installation is needed for those components.
See `lib/README.md` for the supported bundled-library boundary.

On Windows, use forward slashes in INI paths (for example,
`C:/Users/Max/Projects/app`). OODZ Agent selects the UTF-8 console code page at
CLI startup and uses ASCII borders for compatibility with both CMD and
PowerShell. The GUI does not depend on the console code page.

Check the required runtime packages without making a network request:

```bash
tclsh <<'EOF'
foreach package {Tcl Thread tls http json json::write fileutil} {
    puts "$package [package require $package]"
}
EOF
```

## Configuration

Create a private configuration from the published example, restrict its
permissions, and then edit it:

```bash
cp conf/conf.example.ini conf/conf.ini
chmod 600 conf/conf.ini
```

Both Git and Fossil are configured to ignore `conf/conf.ini`. Only
`conf/conf.example.ini`, containing placeholder values and conservative
defaults, belongs in a release.

```ini
[LLM]
provider = deepseek
url = https://api.deepseek.com/chat/completions
api_key = replace-with-your-key
model = deepseek-v4-flash
thinking = false
timeout = 60000
max_retries = 2
retry_delay_ms = 250

[Agent]
name = CoderBot
role = You are an expert Tcl programmer who writes short, clean code.
max_iterations = 16

[Workspace]
root = .

[Plugins]
lazy_loading = true
core = read_file,list_files,search_files,file_info,apply_patch,write_file
worker_thread = true
timeout_ms = 1000
max_output_chars = 65536

[Runner]
enabled = false
tclsh = tclsh9.0
timeout_ms = 10000
max_output_chars = 65536
project_tests_enabled = false
project_tests_executable = tclsh9.0
project_tests_arguments = tests/all.tcl
project_tests_timeout_ms = 60000

[Executables]
fossil = fossil

[GUI]
theme_package = ttk::theme::Arc
theme = Arc-Dark
```

Configuration fields:

- `LLM.provider`: OpenAI-compatible provider identifier: `deepseek` or
  `ollama`.
- `LLM.url`: Full provider chat-completions endpoint.
- `LLM.api_key`: API credential. It is required for DeepSeek and optional for
  local Ollama.
- `LLM.model`: Model identifier sent with each request.
- `Workspace.root`: Filesystem root exposed to tools. Absolute paths are used
  directly; relative paths are resolved from the directory containing
  `main.tcl`. The directory must already exist.
- `Workspace.instructions`: Optional UTF-8 project instruction file relative to
  `Workspace.root`. Its contents are appended to the system prompt on every
  request. The filename is also discovered hierarchically in subdirectories.
- `Workspace.instructions_max_file_bytes`: Maximum size of each hierarchical
  instruction file; defaults to 16384.
- `Workspace.instructions_max_total_bytes`: Maximum combined instructions for
  one target path; defaults to 65536.
- `OODZ.root`: Read-only OODZ framework source root used by framework reference
  tools. The compact lookup index is bundled with `oodz_lookup`.
- `LLM.timeout`: Request timeout in milliseconds; must be positive.
- `LLM.max_retries`: Number of retries after the first attempt; `0` disables
  retries.
- `LLM.retry_delay_ms`: Initial retry delay in milliseconds. Later retry delays
  use exponential backoff.
- `Agent.name`: Name used in agent log messages.
- `Agent.role`: System instruction included before the conversation.
- `Agent.max_iterations`: Maximum DeepSeek/tool cycles allowed for one task.
- `Agent.max_history_messages`: Maximum prior messages sent with a request.
  Complete tool-call turns are retained even when one turn exceeds the limit.
- `Agent.summarize_history`: Reserved switch for automatic history summaries;
  currently defaults to `false` while generation remains disabled.
- `Agent.history_file`: JSON conversation history used by interactive mode,
  resolved relative to the project directory unless absolute.
- `Plugins.timeout_ms`: Tcl execution deadline applied to each plugin call. The
  default is 10 seconds so approved network-backed plugins can complete.
- `Plugins.max_output_chars`: Maximum tool-result size returned to DeepSeek.
- `Plugins.directories`: Optional comma-separated personal plugin directories.
  Absolute paths are used directly; relative paths resolve from the directory
  containing `main.tcl`. The built-in `plugins/` directory is always loaded.
  An optional private `[settings]` manifest section is passed only to the Tcl
  handler and is excluded from model-visible tool definitions.
- `Plugins.lazy_loading`: When true, expose only `Plugins.core`, special
  framework tools, and `search_plugins` to the model initially. A
  `search_plugins` call searches plugin names and manifest descriptions, then
  activates matching definitions for the following model response. Direct CLI
  `/tool` calls can still invoke any installed plugin.
- `Plugins.core`: Comma-separated plugin names that remain model-visible while
  lazy loading is enabled. Startup fails if a configured name is not installed.
- `Plugins.worker_thread`: Run validated and approved plugin handlers serially
  in one persistent Tcl worker thread. The main thread retains metadata,
  activation, validation, approvals, model coordination, and GUI state. This
  improves responsiveness but is not an operating-system security boundary.
- `Skills.directories`: Optional comma-separated personal skill directories.
  The built-in `skills/` directory is always loaded first.
- `Skills.max_file_bytes`: Maximum size of one `SKILL.md`; defaults to 65536.
- `Executables.fossil`: Trusted executable name or absolute path shared by all
  bundled Fossil plugins. The default resolves `fossil` through `PATH`.
- `Runner.enabled`: Expose or remove the controlled `run_tcl_file` tool.
- `Runner.tclsh`: Fixed Tcl interpreter executable used by the runner.
- `Runner.timeout_ms`: Maximum execution time for a Tcl process.
- `Runner.max_output_chars`: Maximum combined standard output/error returned.
- `Runner.project_tests_enabled`: Expose the fixed `run_project_tests` profile.
- `Runner.project_tests_executable`: Trusted executable selected by the user,
  never by the model.
- `Runner.project_tests_arguments`: Trusted Tcl-list arguments passed directly
  without shell evaluation.
- `Runner.project_tests_timeout_ms`: Separate timeout for the complete suite.
- `GUI.theme_package`: Optional Tcl package to load from `lib/` or one of its
  immediate package directories before selecting the theme.
- `GUI.theme`: Optional installed Ttk theme name. Leave it empty to use the
  platform default; the example selects the bundled `Arc-Dark` theme.

Plugin manifests may add optional discovery metadata:

```ini
[plugin]
name = archive_create
description = Create a ZIP archive from a workspace directory.
category = archive
keywords = zip,compress,bundle,backup
platforms = linux,freebsd,windows
requires = helper-command
```

`category` and `keywords` participate in `search_plugins`. `platforms` accepts
`all`, `linux`, `freebsd`, and `windows`; it defaults to `all`. `requires` is a
comma-separated list of executables that must resolve through `PATH`. Plugins
whose platform or executable requirements are unavailable are retained in the
registry's unavailable index but are not exposed or invokable. These fields
are optional, so existing personal manifests remain compatible.

When both Arc variants are installed, the GUI action bar provides a runtime
**Dark** toggle. It changes the current session only; `GUI.theme` remains the
startup preference.
- `Logging.file`: Diagnostic log path, resolved relative to the project unless
  absolute.
- `Logging.level`: Minimum global log level.

The API key remains in the user's private INI file by project decision. Never
commit, archive, or share `conf/conf.ini`; publish only the example. If a key
has ever entered source history or logs, revoke it with the provider and issue
a replacement.

### Ollama

Start Ollama, pull a model with tool-calling support, and use this configuration:

```ini
[LLM]
provider = ollama
url = http://localhost:11434/v1/chat/completions
api_key =
model = qwen3
thinking = false
timeout = 60000
max_retries = 2
retry_delay_ms = 250
```

The model name must match a locally installed Ollama model. Models without tool
support can answer questions but cannot reliably run the agent's plugins.

### Skills

Each skill is a directory containing `SKILL.md` with `name` and `description`
frontmatter followed by concise workflow instructions. Only names and trigger
descriptions are included in the normal system prompt. When a description
matches the task, the model calls the read-only `load_skill` tool to retrieve
that one workflow. This avoids sending every complete skill on every request.

```text
skills/
  create-oodz-class/
    SKILL.md
```

### Hierarchical project instructions

The root configured instruction file is always included in the system prompt.
Before modifying a nested path, the model can call
`load_project_instructions`. The tool searches from the workspace root through
the target directory for files with the configured filename:

```text
project/AGENT.md
project/pages/res/modules/AGENT.md
project/pages/res/modules/report/AGENT.md
```

The root file is not returned again because it is already in the system prompt.
Additional files are returned from the shallowest directory to the closest one.
Closer files refine project conventions for their subtree. Instruction paths
remain confined to the workspace and are subject to per-file and combined size
limits.

### Controlled Tcl execution

> **DANGER — THIS IS NOT A SAFE AGENT.** The default `direct` runner executes
> AI-created Tcl with the same operating-system permissions as the user running
> the agent. It can read, change, or delete accessible files, start processes,
> access the network, and read environment variables. Use this feature only if
> you understand and accept those consequences. Review code and maintain
> recoverable backups or version control.

The optional `run_tcl_file` tool executes one existing workspace-relative
`.tcl` file. It never accepts a model-selected executable or shell command, but
that does not make the Tcl program safe: Tcl itself provides filesystem,
process, and network capabilities. Every execution requires a separate approval;
`All for session` never applies to `run_tcl_file`.

The portable default is:

```ini
[Runner]
enabled = true
tclsh = tclsh9.0
timeout_ms = 10000
max_output_chars = 65536
```

The portable runner enforces the selected file, timeout, and returned-output
limit, but it provides **no filesystem, process, account, environment, or
network isolation**.

Internally, runner methods return a Tcl dictionary containing `status`,
`exit_code`, `output`, `duration_ms`, `timed_out`, and `output_truncated`.
Plugins inspect that native result and decide what concise text to return to
the model; JSON serialization is not required.

OS isolation is deliberately outside the portable core. It can be provided by
optional platform-specific plugins, such as Bubblewrap on Linux or jails on
FreeBSD. Disable execution completely with `Runner.enabled = false`.

#### Fixed project-test profile

Enable a project-specific test command with:

```ini
[Runner]
project_tests_enabled = true
project_tests_executable = tclsh9.0
project_tests_arguments = tests/all.tcl
project_tests_timeout_ms = 60000
```

The model can call `run_project_tests` with an empty argument object, but cannot
change the executable or arguments. Arguments use Tcl list syntax, not shell
syntax, so pipes, redirections, substitutions, and command separators are not
interpreted. The profile uses the same direct runner and output limit as
`run_tcl_file`, and always requires a separate approval.

Run it directly in interactive mode with:

```text
/tool run_project_tests {}
```

### Scoped HTTP GET

The built-in `http_get` plugin sends read-only requests to one plugin-owned
service. Edit `plugins/http_get/plugin.ini` for your local NaviServer instance:

```ini
[settings]
base_url = http://127.0.0.1:8080
allowed_path_prefixes = /api/,/health
timeout_ms = 10000
max_response_chars = 65536
tls_verify = true
tls_ca_file = /path/to/private-ca-or-server-certificate.pem
```

The model supplies only a path and optional query dictionary; it cannot choose
the scheme, host, port, timeout, or allowlist:

```text
/tool http_get {"path":"/health"}
/tool http_get {"path":"/api/v2/client","query":{"page":"2"}}
```

Full URLs, protocol-relative paths, traversal, fragments, embedded query
strings, and paths outside the configured prefixes are rejected. Query data
must be provided separately so it can be percent-encoded. The plugin treats GET
as read-only and therefore does not ask for approval; only configure endpoints
where GET has no mutating behavior.

For a self-signed development certificate, prefer trusting its PEM certificate:

```ini
tls_verify = true
tls_ca_file = /path/to/self-signed-certificate.pem
```

When certificate verification is impractical on a trusted private development
network, it can be disabled explicitly:

```ini
tls_verify = false
tls_ca_file =
```

With verification disabled, HTTPS still encrypts traffic but does not establish
the server's identity. An attacker able to intercept the connection could
impersonate the server. Never disable verification for public or untrusted
networks.

### Scoped JSON POST, PUT, PATCH, and DELETE

The `http_post`, `http_put`, `http_patch`, and `http_delete` plugins use the same
fixed-service, path allowlist, TLS, timeout, and response-size controls as
`http_get`. They are classified as write tools, so the agent asks for approval
before every request. Configure each plugin's private settings independently in
its `plugin.ini`.

Pass the request body as a JSON string. The plugin validates that it is a JSON
object and sends its UTF-8 bytes unchanged, preserving numbers, booleans,
nested values, and native-script translations:

```text
/tool http_post {"path":"/translate/add_new_line","json":"{\"original\":\"Bottle\",\"ru_ru\":\"Бутылка\",\"ch_ch\":\"瓶子\"}"}
/tool http_put {"path":"/client/42","json":"{\"active\":true}"}
/tool http_patch {"path":"/client/42","json":"{\"active\":false}"}
/tool http_delete {"path":"/client/42"}
```

All four support an optional `query` object. POST, PUT, and PATCH require a JSON
body; DELETE accepts one optionally. HTTP error responses are returned with
their status code and body so the agent can explain API validation errors.

Private custom headers can be added to the `[settings]` section of any HTTP
plugin. They are sent on every request from that plugin and are never included
in the tool definition shown to the model:

```ini
header.Authorization = Bearer replace-with-token
header.X-API-Key = replace-with-api-key
header.X-Client-Id = oodz-agent
```

Keep configuration files containing credentials private. Header names and
values containing malformed or newline data are rejected. Transport-controlled
headers such as `Host`, `Content-Length`, `Transfer-Encoding`, `Connection`,
`Accept`, and `Content-Type` cannot be overridden.

### Fossil integration

The read-only `fossil_status` plugin runs the fixed command `fossil status` in
the configured workspace. The model cannot select another command, argument,
or working directory. Execution uses the controlled process runner and inherits
its timeout and output limit.

```text
/tool fossil_status {}
```

Configure the Fossil executable once in the private application configuration;
all bundled Fossil plugins resolve their logical `fossil` command through it:

```ini
[Executables]
fossil = C:/Tools/Fossil/fossil.exe
```

Use forward slashes for Windows paths. The default value `fossil` resolves
through `PATH`.

The read-only `fossil_diff` plugin uses Fossil's internal unified diff engine,
preventing a checkout setting from selecting an external diff program. With no
arguments it shows all uncommitted changes; an optional confined path restricts
the result to one workspace-relative file:

```text
/tool fossil_diff {}
/tool fossil_diff {"path":"src/client.tcl"}
```

`fossil_timeline` displays concise recent check-ins. It defaults to 20 entries;
the caller may request 1–100 entries, with both the default and maximum kept in
private plugin settings:

```text
/tool fossil_timeline {}
/tool fossil_timeline {"limit":50}
```

`fossil_info` reports metadata about the current checkout and checked-out
version. It accepts no model-selected version, repository, or path:

```text
/tool fossil_info {}
```

`fossil_add` schedules one existing workspace-relative file for addition at
the next commit. It requires write approval and does not accept directories,
multiple paths, or extra Fossil options:

```text
/tool fossil_add {"path":"src/new_class.tcl"}
```

`fossil_commit` commits all current checkout changes with a required message.
It requires approval, disables autosync so it does not contact a remote, and
uses `--no-prompt` so warnings fail safely instead of blocking in the
background. The message is passed as one direct process argument and is capped
at 1,000 characters by default:

```text
/tool fossil_commit {"message":"Add the client account class"}
```

`fossil_revert` discards uncommitted changes in exactly one existing file and
requires approval. It never reverts a directory or the whole checkout and does
not accept a revision. Fossil's normal undo snapshot remains enabled, so an
accidental revert can usually be recovered with `fossil undo`:

```text
/tool fossil_revert {"path":"src/client.tcl"}
```

`fossil_update` updates the whole checkout to its unique descendant leaf while
retaining uncommitted changes. It requires approval, disables autosync, and
accepts no model-selected version, file, repository, or extra option. If the
local history has multiple possible leaves, Fossil fails instead of choosing
one implicitly:

```text
/tool fossil_update {}
```

`fossil_undo` restores exactly one confined path from Fossil's single-level
undo snapshot. The path is allowed to be missing because undo can restore a
deleted file. It requires approval and cannot undo the whole checkout:

```text
/tool fossil_undo {"path":"src/client.tcl"}
```

`fossil_redo` reapplies the most recently undone change to exactly one confined
path. Like undo, it allows a missing target and requires approval:

```text
/tool fossil_redo {"path":"src/client.tcl"}
```

`fossil_remove` marks exactly one existing file as removed from Fossil and
deletes it from disk using explicit `--hard` behavior. It requires approval,
rejects directories, and is not recoverable through `fossil_undo`; recovery
must use the checked-in version, for example with `fossil_revert`:

```text
/tool fossil_remove {"path":"src/obsolete.tcl"}
```

`fossil_changes` gives a concise, classified list of the managed files that
would be included in the next commit. It uses workspace-relative paths, omits
merge-contributor noise, and prints `(none)` when the checkout is clean:

```text
/tool fossil_changes {}
```

`fossil_extras` lists unmanaged files that may need to be added. It forces
workspace-relative output and leaves hidden-file and ignore-glob policy under
the checkout owner's control:

```text
/tool fossil_extras {}
```

`fossil_ls` lists every managed file in the checkout together with its current
status. It accepts no model-selected paths, versions, repositories, or options:

```text
/tool fossil_ls {}
```

`fossil_branches` lists all branches, including closed branches. Fossil marks
the current branch with an asterisk and private branches with a hash sign:

```text
/tool fossil_branches {}
```

Inspect one branch in more detail with `fossil_branch_info`:

```text
/tool fossil_branch_info {"name":"release/v2"}
```

Create a local branch from a named basis check-in with `fossil_branch_new`.
The operation requires approval, disables autosync, and does not switch the
working checkout to the new branch:

```text
/tool fossil_branch_new {"name":"feature/accounts","basis":"trunk"}
```

Switch the entire checkout to a branch with `fossil_branch_switch`. Fossil
retains and reapplies uncommitted changes; the operation requires approval and
does not contact a remote server:

```text
/tool fossil_branch_switch {"name":"feature/accounts"}
```

Close a completed branch with `fossil_branch_close`. Closing adds Fossil's
closed marker; it does not delete the branch or its history. The operation
requires approval and disables autosync:

```text
/tool fossil_branch_close {"name":"feature/accounts"}
```

Reverse that marker with `fossil_branch_reopen`. It requires approval and
disables autosync just like close:

```text
/tool fossil_branch_reopen {"name":"feature/accounts"}
```

Merge one branch or check-in into the current checkout with `fossil_merge`:

```text
/tool fossil_merge {"source":"feature/accounts"}
```

Merge requires approval, disables autosync, accepts exactly one bounded source,
and leaves the result uncommitted for inspection. Fossil's undo recording stays
enabled. Conflicts are returned to the agent and may require manual resolution.

Use the bounded stash workflow to temporarily set aside all checkout changes:

```text
/tool fossil_stash_list {}
/tool fossil_stash_save {"comment":"Pause account form work"}
/tool fossil_stash_pop {}
```

Listing is read-only. Save requires a comment and approval, records all current
changes, and reverts the checkout to its baseline. Pop also requires approval;
it applies the newest stash, removes that stash entry, and may produce merge
conflicts. The tools intentionally accept neither file paths nor stash IDs.

The automated test suite also creates a temporary real Fossil repository and
exercises discovery, add, commit, branch creation, branch inspection, and
branch switching through the plugin registry. The integration test is skipped
when the `fossil` executable is unavailable and never uses a configured remote.

`fossil_pull` is the first explicit network-enabled Fossil operation. It pulls
public sharable changes into the local repository using only the checkout's
configured default remote. It requires approval, accepts no URL, credentials,
repository path, or options, and does not update the working files:

```text
/tool fossil_pull {}
```

`fossil_push` sends public sharable changes to that same configured default
remote. It also requires approval and accepts no URL, credentials, repository
path, private-branch flag, or other options:

```text
/tool fossil_push {}
```

## Usage

Start an interactive session:

```bash
tclsh main.tcl
```

Or start the Tk/ttk desktop interface:

```bash
wish gui.tcl
```

The desktop interface provides a conversation view, multiline input,
streaming responses, persistent history, New/Send controls, and write approval
dialogs. Its Tools dialog lists every available tool, displays its description
and JSON argument schema, and can invoke it locally without calling the LLM.
Press `Ctrl+Enter` to send a prompt or run a selected tool. It uses the same
configuration, workspace, plugins, and OODZ reference as the terminal interface.

The same agent remains active across prompts, so conversation and tool history
carry into follow-up tasks. Assistant content streams to the terminal as DeepSeek
produces it. Interactive commands:

- `/help`: Show available commands.
- `/multi`: Collect multiline input until `/send`; abort with `/cancel`.
- `/tools`: List loaded tool plugins.
- `/skills`: List discovered skills and their trigger descriptions.
- `/tool name ?JSON?`: Run a plugin locally without calling DeepSeek. Arguments
  default to `{}` when omitted.
- `/oodz_trns label`: Translate a label into all configured native-language
  scripts and save it through `save_translation`.
- `/history`: Display the current conversation.
- `/logs`: Display the latest 20 diagnostic log entries.
- `/new`: Clear history and start a new conversation.
- `/exit` or `/quit`: End the session.

For example:

```text
/tool list_files {}
/tool file_info {"path":"main.tcl"}
/tool xml_validate {"path":"layout.xml"}
```

Direct tool calls use the same schemas, workspace confinement, execution limits,
and write approvals as model-selected calls.

For one-shot/scripted use, pass the task as arguments:

Pass the task as command-line arguments:

```bash
tclsh main.tcl "Write a simple puts loop."
```

One-shot output remains buffered so standard output contains one complete final
answer.

Quoting is recommended for tasks containing spaces. Multiple unquoted arguments
are joined with spaces.

Show help:

```bash
tclsh main.tcl --help
```

The final answer is written to standard output. Logs and errors are written to
standard error.

Exit codes:

- `0`: success or help
- `1`: configuration, transport, API, or parsing failure
- `2`: no task was provided

To test an approved write, use a disposable filename:

```bash
tclsh main.tcl \
  "Create agent-write-test.txt containing exactly: DeepSeek agent write test"
```

If DeepSeek selects `write_file`, the CLI displays the plugin name and target
path. Enter `y` or `yes` to allow that one write; any other response denies it.
Inspect and remove the disposable file after the test.

Paths are resolved relative to `main.tcl`, so the program can be launched from
another working directory:

```bash
tclsh /path/to/oodz_agent/main.tcl "Write a simple puts loop."
```

## Tests

Run the complete project test suite:

```bash
tclsh9.0 tests/all.tcl
```

The tests use fake clients and transports. They do not require a real API key and
do not make network calls. The command returns a non-zero exit status if any
project test fails.

Each area is also independently runnable:

```bash
# One test file
tclsh9.0 tests/plugin_registry.test

# One or more named tests
tclsh9.0 tests/plugin_registry.test \
  -match 'plugins-metadata-* plugins-lazy-*'

# Select one file through the aggregate runner
tclsh9.0 tests/all.tcl -file agent.test
```

Shared fake clients, transports, mocks, constraints, and temporary-directory
handling live in `tests/support.tcl`. Test fixtures remain under
`tests/fixtures/`.

Tests shipped inside `lib/` belong to the bundled dependencies and are not part
of this project verification command.

A successful run ends with output similar to:

```text
all.tcl: Total 123 Passed 123 Skipped 0 Failed 0
```

The same test command can be invoked with an absolute path from outside the
repository.

## Current scope

The supported path is:

```text
CLI -> tAgent -> DeepSeek
               -> plugin registry -> read_file/list_files/search_files/file_info/xml_validate
                                     oodz_lookup/oodz_search/oodz_read
                                     save_translation
                                     make_directory/edit_file/apply_patch
                                     copy_file/move_file/delete_file/write_file
                                     zip/unzip
```

Conversation and tool-call history is saved after each successful interactive
turn and restored on the next launch. `/new` clears both memory and the stored
history. All filesystem-changing plugins require interactive approval before
every invocation.
Interactive answers are streamed as they arrive. Multiple providers remain
deferred.

Interactive terminal chrome uses the bundled Zesty package for color and a
compact startup banner. Styling is disabled for redirected/test channels and
when `NO_COLOR` is set, while one-shot output remains plain for scripting.
When the optional `tclreadline` package is installed, interactive input gains
cursor movement, editing, and persistent history in `.oodz/readline-history`.
Redirected input retains the plain `gets` path.

`search_files` performs a recursive, case-insensitive literal text search within
the workspace. It skips `.git`, files larger than 1 MiB, and unreadable files,
and returns at most 100 matching lines.

## OODZ framework context

OODZ framework source is registered separately from the writable project:

```ini
[OODZ]
root = /opt/ns/tcl/oodz
```

Use `oodz_lookup` to discover a component, `oodz_search` to locate exact APIs,
and `oodz_read` to retrieve a bounded numbered source range. The framework and
its complete index are not sent automatically; only returned tool results enter
the conversation. See `docs/oodz-framework.html` for configuration, token
behavior, direct examples, access boundaries, and index maintenance.

See `PLAN.md` for the incremental implementation roadmap.

Tool plugins live under `plugins/`. See `plugins/README.md` for the manifest,
handler, validation, and trust contract used by built-in and user-created tools.
