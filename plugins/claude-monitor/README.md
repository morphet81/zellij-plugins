# Claude Monitor

A native Zellij WASM plugin that displays colored status indicators in tab names to reflect the state of Claude Code sessions.

| Icon | State | Meaning |
|------|-------|---------|
| 🔵 | Working | Claude is processing or generating |
| 🟡 | Waiting | Claude needs user input (permission prompt, elicitation dialog) |
| 🟢 | Ready | New session or `/clear` — Claude is ready for first input |
| _(none)_ | No session | No active Claude Code sessions in this tab |

When multiple Claude Code sessions run in the same tab, the icon reflects the highest-priority state: **waiting > working > idle**. The original tab name is preserved and restored when all sessions exit.

## How It Works

The plugin has two components:

### 1. WASM Plugin (`claude-tab-monitor.wasm`)

A Rust plugin compiled to WebAssembly that runs inside Zellij. On load, it requests `ReadApplicationState` and `ChangeApplicationState` permissions and subscribes to `TabUpdate` and `PaneUpdate` events.

It receives state updates through [Zellij pipes](https://zellij.dev/documentation/plugin-pipes) on a named channel called `claude-status`. Each message is a JSON payload:

```json
{"pane_id": "<zellij-pane-id>", "state": "<working|waiting|idle|exit>"}
```

The plugin maintains a map of pane IDs to their Claude Code state. When a state change arrives, it:

1. Records the pane's new state (or removes it on `exit`)
2. Looks up which tab the pane belongs to (using data from `PaneUpdate` events)
3. Computes the aggregate state for that tab (highest priority across all tracked panes)
4. Prepends the corresponding icon to the tab name via `rename_tab()`

On `TabUpdate`, the plugin tracks current tab names and strips any existing icon prefix to maintain a clean "original" name. When all Claude sessions in a tab exit, the original name is restored.

### 2. Hook Script (`hook.sh`)

A POSIX shell script that bridges Claude Code and the WASM plugin. It is invoked by [Claude Code hooks](https://docs.anthropic.com/en/docs/claude-code/hooks) with a single argument (`working`, `waiting`, `idle`, or `exit`).

The script:
- Exits silently if not running inside Zellij (`$ZELLIJ` / `$ZELLIJ_PANE_ID` unset)
- Sends a JSON payload to the plugin via `zellij pipe --plugin <path> --name claude-status`
- Uses the `--plugin` flag so Zellij auto-launches the plugin if it isn't already running
- Runs the pipe command in the background (`&`) to avoid blocking Claude Code hooks

No polling, no file-based state, no screen scraping — everything is event-driven.

## Claude Code Hooks

The installer configures these automatically. If you installed manually, add them to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [
      { "matcher": "startup", "hooks": [{ "type": "command", "command": "$HOME/.config/zellij/plugins/hook.sh idle" }] },
      { "matcher": "clear", "hooks": [{ "type": "command", "command": "$HOME/.config/zellij/plugins/hook.sh idle" }] }
    ],
    "UserPromptSubmit": [
      { "matcher": "", "hooks": [{ "type": "command", "command": "$HOME/.config/zellij/plugins/hook.sh working" }] }
    ],
    "PostToolUse": [
      { "matcher": "", "hooks": [{ "type": "command", "command": "$HOME/.config/zellij/plugins/hook.sh working" }] }
    ],
    "Stop": [
      { "matcher": "", "hooks": [{ "type": "command", "command": "$HOME/.config/zellij/plugins/hook.sh exit" }] }
    ],
    "Notification": [
      { "matcher": "permission_prompt", "hooks": [{ "type": "command", "command": "$HOME/.config/zellij/plugins/hook.sh waiting" }] },
      { "matcher": "elicitation_dialog", "hooks": [{ "type": "command", "command": "$HOME/.config/zellij/plugins/hook.sh waiting" }] }
    ],
    "SessionEnd": [
      { "matcher": "", "hooks": [{ "type": "command", "command": "$HOME/.config/zellij/plugins/hook.sh exit" }] }
    ]
  }
}
```

## Optional: Layout-Based Loading

Instead of relying on auto-launch, you can load the plugin via a Zellij layout. A sample `layout.kdl` is included:

```kdl
layout {
    pane size=1 borderless=true {
        plugin location="file:~/.config/zellij/plugins/claude-tab-monitor.wasm"
    }
    pane
}
```

Start Zellij with: `zellij --layout layout.kdl`

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
- Verify you are inside Zellij: `echo $ZELLIJ`
- Check the plugin is loaded: `zellij plugin -- file:~/.config/zellij/plugins/claude-tab-monitor.wasm`
- Verify hooks are configured: `grep hook.sh ~/.claude/settings.json`

**Icon stuck after Claude exits:**
- The `SessionEnd` hook sends an `exit` event to clean up. If Claude was killed with SIGKILL, cleanup may not fire.
- Manually restore with: `zellij action rename-tab "your-tab-name"`

**Hooks not firing:**
- Ensure your Claude Code version supports hooks
- Validate the settings file: `jq . ~/.claude/settings.json`

## Requirements

- [Zellij](https://zellij.dev/) 0.40+
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) with hooks support
- `jq` (for automatic hooks setup during install/uninstall)
