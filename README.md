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

**Claude Code** uses native hooks — event-driven, instant, and reliable:

- `UserPromptSubmit` / `PostToolUse` hooks → working
- `Notification(permission_prompt)` hook → waiting
- `Stop` / `Notification(idle_prompt)` hooks → idle
- `SessionEnd` hook → cleanup and restore tab name

No polling, no screen scraping, no pattern matching. State changes are detected the instant they happen.

**Cursor Agent** falls back to periodic screen monitoring (same approach works for any terminal-based agent):

- Screen content changing between checks → working
- Screen stable for ~3 seconds → checks for prompt patterns (waiting) or defaults to idle

### Install

**One-liner:**

```sh
curl -fsSL https://raw.githubusercontent.com/morphet81/zellij-plugins/main/install.sh | bash
```

The install script will:
1. Download `ai-tab-monitor.zsh` and `ai-tab-monitor-hook.sh`
2. Offer to add the source line to your `.zshrc`
3. Offer to configure Claude Code hooks in `~/.claude/settings.json` (requires `jq`)

**Manual:**

```sh
mkdir -p ~/.config/zellij/plugins
curl -fsSL https://raw.githubusercontent.com/morphet81/zellij-plugins/main/ai-tab-monitor.zsh \
  -o ~/.config/zellij/plugins/ai-tab-monitor.zsh
curl -fsSL https://raw.githubusercontent.com/morphet81/zellij-plugins/main/ai-tab-monitor-hook.sh \
  -o ~/.config/zellij/plugins/ai-tab-monitor-hook.sh
chmod +x ~/.config/zellij/plugins/ai-tab-monitor-hook.sh
```

Then add to your `.zshrc`:

```zsh
source ~/.config/zellij/plugins/ai-tab-monitor.zsh
```

### Claude Code hooks setup

For instant state detection, add these hooks to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {"matcher": "", "hooks": [{"type": "command", "command": "bash \"$HOME/.config/zellij/plugins/ai-tab-monitor-hook.sh\" working"}]}
    ],
    "PostToolUse": [
      {"matcher": "", "hooks": [{"type": "command", "command": "bash \"$HOME/.config/zellij/plugins/ai-tab-monitor-hook.sh\" working"}]}
    ],
    "Stop": [
      {"matcher": "", "hooks": [{"type": "command", "command": "bash \"$HOME/.config/zellij/plugins/ai-tab-monitor-hook.sh\" idle"}]}
    ],
    "Notification": [
      {"matcher": "permission_prompt", "hooks": [{"type": "command", "command": "bash \"$HOME/.config/zellij/plugins/ai-tab-monitor-hook.sh\" waiting"}]},
      {"matcher": "idle_prompt", "hooks": [{"type": "command", "command": "bash \"$HOME/.config/zellij/plugins/ai-tab-monitor-hook.sh\" idle"}]},
      {"matcher": "elicitation_dialog", "hooks": [{"type": "command", "command": "bash \"$HOME/.config/zellij/plugins/ai-tab-monitor-hook.sh\" waiting"}]}
    ],
    "SessionEnd": [
      {"matcher": "", "hooks": [{"type": "command", "command": "bash \"$HOME/.config/zellij/plugins/ai-tab-monitor-hook.sh\" cleanup"}]}
    ]
  }
}
```

> **Note:** Without hooks, Claude Code still works but falls back to the wrapper-only approach (shows idle on start, restores on exit — no working/waiting detection).

### Usage

Just run `claude` or `cursor-agent` as usual inside Zellij. The tab name updates automatically.

### Configuration

All settings are optional environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `AI_TAB_POLL_INTERVAL` | `1` | Seconds between screen checks (Cursor Agent only) |
| `AI_TAB_WAITING_ICON` | `🟡` | Icon for waiting state |
| `AI_TAB_WORKING_ICON` | `🔵` | Icon for working state |
| `AI_TAB_IDLE_ICON` | `🟢` | Icon for idle state |

Example:

```zsh
export AI_TAB_POLL_INTERVAL=2
export AI_TAB_IDLE_ICON="⚪"
source ~/.config/zellij/plugins/ai-tab-monitor.zsh
```

### Requirements

- [Zellij](https://zellij.dev/) terminal multiplexer
- zsh
- For Claude Code hooks: Claude Code with hooks support
- For Cursor Agent: `md5` (macOS) or `md5sum` (Linux)
