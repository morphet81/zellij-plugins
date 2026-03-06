# Claude Tab Monitor for Zellij

A native Zellij WASM plugin that shows colored status pills in tab names based on Claude Code session state.

| Icon | State | Meaning |
|------|-------|---------|
| 🔵 | Working | Claude is processing or generating |
| 🟡 | Waiting | Claude needs user approval (permission prompt) |
| 🟢 | Idle | Claude is ready for a new prompt |
| _(none)_ | No session | No active Claude sessions in this tab |

The original tab name is preserved and restored when all sessions exit.

When multiple Claude sessions run in the same tab, the icon reflects the highest-priority state: **waiting > working > idle**.

## Quick Install

```sh
curl -fsSL https://raw.githubusercontent.com/morphet81/zellij-plugins/main/install.sh | bash
```

The install script will:
1. Download `claude-tab-monitor.wasm` and `hook.sh` to `~/.config/zellij/plugins/`
2. Offer to configure Claude Code hooks in `~/.claude/settings.json` (requires `jq`)

## Manual Install

```sh
mkdir -p ~/.config/zellij/plugins

# Download the WASM plugin (from releases)
curl -fsSL https://github.com/morphet81/zellij-plugins/releases/latest/download/claude-tab-monitor.wasm \
  -o ~/.config/zellij/plugins/claude-tab-monitor.wasm

# Download the hook script
curl -fsSL https://raw.githubusercontent.com/morphet81/zellij-plugins/main/hook.sh \
  -o ~/.config/zellij/plugins/hook.sh
chmod +x ~/.config/zellij/plugins/hook.sh
```

## Loading the Plugin

The WASM plugin must be running in your Zellij session. Add it to your layout:

```kdl
layout {
    pane size=1 borderless=true {
        plugin location="file:~/.config/zellij/plugins/claude-tab-monitor.wasm"
    }
    pane
}
```

Or load it manually:

```sh
zellij plugin -- file:~/.config/zellij/plugins/claude-tab-monitor.wasm
```

## Claude Code Hooks

Add these hooks to `~/.claude/settings.json` (the install script does this automatically):

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {"matcher": "", "hooks": [{"type": "command", "command": "$HOME/.config/zellij/plugins/hook.sh working"}]}
    ],
    "PostToolUse": [
      {"matcher": "", "hooks": [{"type": "command", "command": "$HOME/.config/zellij/plugins/hook.sh working"}]}
    ],
    "Stop": [
      {"matcher": "", "hooks": [{"type": "command", "command": "$HOME/.config/zellij/plugins/hook.sh idle"}]}
    ],
    "Notification": [
      {"matcher": "permission_prompt", "hooks": [{"type": "command", "command": "$HOME/.config/zellij/plugins/hook.sh waiting"}]},
      {"matcher": "idle_prompt", "hooks": [{"type": "command", "command": "$HOME/.config/zellij/plugins/hook.sh idle"}]},
      {"matcher": "elicitation_dialog", "hooks": [{"type": "command", "command": "$HOME/.config/zellij/plugins/hook.sh waiting"}]}
    ],
    "SessionEnd": [
      {"matcher": "", "hooks": [{"type": "command", "command": "$HOME/.config/zellij/plugins/hook.sh exit"}]}
    ]
  }
}
```

## How It Works

1. **WASM Plugin** (`claude-tab-monitor.wasm`) — runs inside Zellij, subscribes to tab/pane events, receives state updates via `zellij pipe`, tracks state per pane, aggregates per tab, renames tabs with pill prefixes
2. **Hook script** (`hook.sh`) — 13-line POSIX shell script called by Claude Code hooks (including `SessionEnd`), sends `zellij pipe --name claude-status -- '{"pane_id":"...","state":"..."}'`

State changes are event-driven via Claude Code hooks — no polling, no screen scraping, no file-based state, no zsh wrapper, no locking.

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `ZELLIJ_PLUGIN_DIR` | `~/.config/zellij/plugins` | Custom install directory |

## Uninstall

```sh
curl -fsSL https://raw.githubusercontent.com/morphet81/zellij-plugins/main/uninstall.sh | bash
```

## Building from Source

Requires Rust with the `wasm32-wasip1` target:

```sh
rustup target add wasm32-wasip1
cd plugin
cargo build --release --target wasm32-wasip1
# Output: target/wasm32-wasip1/release/claude-tab-monitor.wasm
```

## Troubleshooting

**Tab name not updating:**
- Verify you are inside Zellij (`echo $ZELLIJ`)
- Check the plugin is loaded (`zellij plugin -- file:~/.config/zellij/plugins/claude-tab-monitor.wasm`)
- Verify hooks are configured: `grep hook.sh ~/.claude/settings.json`

**Icon stuck after Claude exits:**
- The zsh wrapper sends an exit event on session end; if Claude was killed with SIGKILL, cleanup may not fire
- Run `zellij action rename-tab "your-tab-name"` to manually restore

**Hooks not firing:**
- Ensure Claude Code version supports hooks
- Check `~/.claude/settings.json` is valid JSON (`jq . ~/.claude/settings.json`)

## Requirements

- [Zellij](https://zellij.dev/) 0.40+
- Claude Code with hooks support
- `jq` (for automatic hooks setup during install)
