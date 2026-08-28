# Bundled library support

The application adds this directory to Tcl's package path. These bundled
packages are part of the supported OODZ Agent runtime:

| Package | Supported use |
| --- | --- |
| `inifile` 0.3.3 | Reading and writing INI files |
| `tConfClass` 1.0 | Configuration object with the INI backend |
| `tLogger` 1.0.0 | Application diagnostics |
| `zesty` 0.2 | Interactive terminal styling and banner rendering |
| `oodzMarkdownTk` 0.1.0 | Incremental, inert Markdown styling for Tk text widgets |

The project test suite covers package loading, an INI save/load round trip,
logger use through the application, and the Zesty presentation integration.

## Optional tConf backends

The JSON, YAML, and SQLite files under `tConf/backends/` are retained as
upstream/experimental code. They are not sourced by `tConfClass`'s package
index, are not used by OODZ Agent, and are not currently supported or tested.
Do not select them for production configuration without a separate integration
and test step.

OODZ Agent's API JSON handling is unrelated to the optional tConf JSON backend;
it uses Tcllib's installed `json` and `json::write` packages directly.
