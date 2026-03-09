# Zellij Plugins

## Project Structure
- `plugins/` - Each subdirectory is an independent plugin
- `plugins/claude-monitor/` - Claude Tab Monitor plugin
  - `plugin/` - Rust WASM plugin (Cargo project, target: wasm32-wasip1)
  - `hook.sh` - POSIX shell script called by Claude Code hooks
  - `layout.kdl` - Sample Zellij layout that auto-loads the plugin
  - `plugin.conf` - Plugin metadata (name, description, wasm filename)
  - `install.sh` / `uninstall.sh` - Plugin-specific install/uninstall logic
- `install.sh` / `uninstall.sh` - Root interactive plugin selector scripts

## Build
```sh
cd plugins/claude-monitor/plugin && cargo build --release --target wasm32-wasip1
```

## Architecture
1. WASM plugin runs inside Zellij, subscribes to TabUpdate/PaneUpdate events
2. Claude Code hooks (including SessionEnd) call `hook.sh <state>` which sends JSON via `zellij pipe`
3. Plugin tracks state per pane, aggregates per tab, renames tabs with pill prefix

## Protocol
- Pipe name: `claude-status`
- Payload: `{"pane_id":"<id>","state":"<working|waiting|idle|exit>"}`
- State priority: waiting > working > idle

## Adding a New Plugin
1. Create `plugins/<name>/` with a `plugin.conf` (PLUGIN_NAME, PLUGIN_DESC, WASM_NAME)
2. Add `install.sh` and `uninstall.sh` in the plugin directory
3. Plugin scripts are `source`d by the root scripts; they can use `info`, `success`, `warn`, `error`, `confirm` helpers and the `INSTALL_DIR` env var

## Conventions
- Rust edition 2021, zellij-tile 0.43.0
- POSIX shell for `hook.sh` (no bash-isms)
- Bash for `install.sh` / `uninstall.sh`
