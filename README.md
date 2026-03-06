# zellij-plugins

Zellij tab status indicators for AI coding agents.

## ai-tab-monitor

Monitors [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and [Cursor Agent](https://docs.cursor.com/agent) sessions running in Zellij, showing their status as a colored icon prepended to the tab name.

| Icon | State | Meaning |
|------|-------|---------|
| 🟢 | Idle | Agent is ready for a new query |
| 🔵 | Working | Agent is processing or generating |
| 🟡 | Waiting | Agent needs user approval (permission prompt) |

The original tab name is preserved and restored when all sessions exit.

When multiple sessions run in the same tab, the icon reflects the highest-priority state: **waiting > working > idle**.

### How it works

The plugin uses `zellij action dump-screen` to periodically capture the terminal content and detect state changes:

- **Screen changing** between checks → working
- **Screen stable** for ~2 seconds → checks for approval prompt patterns (waiting) or defaults to idle

No CPU monitoring, no process introspection — just direct observation of terminal output.

### Install

**One-liner:**

```sh
curl -fsSL https://raw.githubusercontent.com/morphet81/zellij-plugins/main/install.sh | bash
```

**Manual:**

```sh
mkdir -p ~/.config/zellij/plugins
curl -fsSL https://raw.githubusercontent.com/morphet81/zellij-plugins/main/ai-tab-monitor.zsh \
  -o ~/.config/zellij/plugins/ai-tab-monitor.zsh
```

Then add to your `.zshrc`:

```zsh
source ~/.config/zellij/plugins/ai-tab-monitor.zsh
```

### Usage

Just run `claude` or `cursor-agent` as usual inside Zellij. The tab name updates automatically.

### Configuration

All settings are optional environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `AI_TAB_POLL_INTERVAL` | `0.5` | Seconds between screen checks |
| `AI_TAB_WAITING_ICON` | `🟡` | Icon for waiting state |
| `AI_TAB_WORKING_ICON` | `🔵` | Icon for working state |
| `AI_TAB_IDLE_ICON` | `🟢` | Icon for idle state |

Example:

```zsh
export AI_TAB_POLL_INTERVAL=1
export AI_TAB_IDLE_ICON="⚪"
source ~/.config/zellij/plugins/ai-tab-monitor.zsh
```

### Requirements

- [Zellij](https://zellij.dev/) terminal multiplexer
- zsh
- `md5` (macOS) or `md5sum` (Linux)
