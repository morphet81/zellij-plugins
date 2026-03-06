# Claude Tab Monitor

## Project Structure
- `plugin/` - Rust WASM plugin (Cargo project, target: wasm32-wasip1)
- `hook.sh` - POSIX shell script called by Claude Code hooks
- `install.sh` / `uninstall.sh` - Installation and uninstallation scripts
- `layout.kdl` - Sample Zellij layout that auto-loads the plugin

## Build
```sh
cd plugin && cargo build --release --target wasm32-wasip1
```

## Architecture
1. WASM plugin runs inside Zellij, subscribes to TabUpdate/PaneUpdate events
2. Claude Code hooks (including SessionEnd) call `hook.sh <state>` which sends JSON via `zellij pipe`
3. Plugin tracks state per pane, aggregates per tab, renames tabs with pill prefix

## Protocol
- Pipe name: `claude-status`
- Payload: `{"pane_id":"<id>","state":"<working|waiting|idle|exit>"}`
- State priority: waiting > working > idle

## Conventions
- Rust edition 2021, zellij-tile 0.43.0
- POSIX shell for `hook.sh` (no bash-isms)
- Bash for `install.sh` / `uninstall.sh`
