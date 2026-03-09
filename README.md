# Claude Tab Monitor for Zellij

A native Zellij WASM plugin that displays colored status indicators in tab names to reflect the state of Claude Code sessions.

| Icon | State | Meaning |
|------|-------|---------|
| 🔵 | Working | Claude is processing or generating |
| 🟡 | Waiting | Claude needs user input (permission prompt, elicitation dialog) |
| 🟢 | Idle | Claude is ready for a new prompt |
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

A 13-line POSIX shell script that bridges Claude Code and the WASM plugin. It is invoked by [Claude Code hooks](https://docs.anthropic.com/en/docs/claude-code/hooks) with a single argument (`working`, `waiting`, `idle`, or `exit`).

The script:
- Exits silently if not running inside Zellij (`$ZELLIJ` / `$ZELLIJ_PANE_ID` unset)
- Sends a JSON payload to the plugin via `zellij pipe --plugin <path> --name claude-status`
- Uses the `--plugin` flag so Zellij auto-launches the plugin if it isn't already running
- Runs the pipe command in the background (`&`) to avoid blocking Claude Code hooks

No polling, no file-based state, no screen scraping — everything is event-driven.

## Install

### Quick Install (remote)

```sh
curl -fsSL https://raw.githubusercontent.com/morphet81/zellij-plugins/main/install.sh | bash
```

### Quick Install (local clone)

```sh
git clone https://github.com/morphet81/zellij-plugins.git
cd zellij-plugins
./install.sh
```

When run from a local clone, the installer builds the WASM plugin from source (requires the Rust toolchain with the `wasm32-wasip1` target). When run remotely via curl, it downloads a prebuilt `.wasm` from GitHub releases.

### What the Installer Does

1. Downloads (or builds) `claude-tab-monitor.wasm` and `hook.sh` into `~/.config/zellij/plugins/`
2. Offers to configure Claude Code hooks in `~/.claude/settings.json` (requires `jq`)

The plugin auto-launches when Claude Code hooks first fire — no layout changes are needed. Zellij will prompt for plugin permissions on first use.

### Installer Options

| Flag | Description |
|------|-------------|
| `-d, --dir <path>` | Custom install directory (default: `~/.config/zellij/plugins`) |
| `-y, --yes` | Skip confirmation prompts |
| `-h, --help` | Show help |

You can also set the `ZELLIJ_PLUGIN_DIR` environment variable to change the install directory.

### Manual Install

If you prefer to install manually:

```sh
mkdir -p ~/.config/zellij/plugins

# Download the WASM plugin
curl -fsSL https://github.com/morphet81/zellij-plugins/releases/latest/download/claude-tab-monitor.wasm \
  -o ~/.config/zellij/plugins/claude-tab-monitor.wasm

# Download the hook script
curl -fsSL https://raw.githubusercontent.com/morphet81/zellij-plugins/main/hook.sh \
  -o ~/.config/zellij/plugins/hook.sh
chmod +x ~/.config/zellij/plugins/hook.sh
```

Then add the hooks to `~/.claude/settings.json` manually (see [Claude Code Hooks](#claude-code-hooks) below).

### Claude Code Hooks

The installer configures these automatically. If you installed manually, add them to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      { "matcher": "", "hooks": [{ "type": "command", "command": "$HOME/.config/zellij/plugins/hook.sh working" }] }
    ],
    "PostToolUse": [
      { "matcher": "", "hooks": [{ "type": "command", "command": "$HOME/.config/zellij/plugins/hook.sh working" }] }
    ],
    "Stop": [
      { "matcher": "", "hooks": [{ "type": "command", "command": "$HOME/.config/zellij/plugins/hook.sh idle" }] }
    ],
    "Notification": [
      { "matcher": "permission_prompt", "hooks": [{ "type": "command", "command": "$HOME/.config/zellij/plugins/hook.sh waiting" }] },
      { "matcher": "idle_prompt", "hooks": [{ "type": "command", "command": "$HOME/.config/zellij/plugins/hook.sh idle" }] },
      { "matcher": "elicitation_dialog", "hooks": [{ "type": "command", "command": "$HOME/.config/zellij/plugins/hook.sh waiting" }] }
    ],
    "SessionEnd": [
      { "matcher": "", "hooks": [{ "type": "command", "command": "$HOME/.config/zellij/plugins/hook.sh exit" }] }
    ]
  }
}
```

### Optional: Layout-Based Loading

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

## Uninstall

### Quick Uninstall

```sh
curl -fsSL https://raw.githubusercontent.com/morphet81/zellij-plugins/main/uninstall.sh | bash
```

Or from a local clone:

```sh
./uninstall.sh
```

### What the Uninstaller Does

1. Removes Claude Code hooks referencing `hook.sh` from `~/.claude/settings.json` (requires `jq`)
2. Deletes `claude-tab-monitor.wasm` and `hook.sh` from the plugin directory
3. Cleans up any legacy files from earlier versions of the plugin

### Uninstaller Options

| Flag | Description |
|------|-------------|
| `-d, --dir <path>` | Plugin directory (default: `~/.config/zellij/plugins`) |
| `-y, --yes` | Skip confirmation prompts |
| `-h, --help` | Show help |

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
