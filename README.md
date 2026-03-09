# Zellij Plugins

A collection of plugins for [Zellij](https://zellij.dev/), the terminal workspace.

## Available Plugins

| Plugin | Description |
|--------|-------------|
| [Claude Monitor](plugins/claude-monitor/) | Shows Claude Code activity state as emoji pills on Zellij tab names |

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

The installer presents an interactive selector to choose which plugins to install. When run from a local clone, WASM plugins are built from source (requires the Rust toolchain with the `wasm32-wasip1` target). When run remotely via curl, prebuilt `.wasm` files are downloaded from GitHub releases.

### Installer Options

| Flag | Description |
|------|-------------|
| `-d, --dir <path>` | Custom install directory (default: `~/.config/zellij/plugins`) |
| `-y, --yes` | Skip confirmation prompts |
| `-h, --help` | Show help |

You can also set the `ZELLIJ_PLUGIN_DIR` environment variable to change the install directory.

## Uninstall

```sh
curl -fsSL https://raw.githubusercontent.com/morphet81/zellij-plugins/main/uninstall.sh | bash
```

Or from a local clone:

```sh
./uninstall.sh
```

The uninstaller lets you select which plugins to remove and cleans up any associated configuration.

### Uninstaller Options

| Flag | Description |
|------|-------------|
| `-d, --dir <path>` | Plugin directory (default: `~/.config/zellij/plugins`) |
| `-y, --yes` | Skip confirmation prompts |
| `-h, --help` | Show help |

## Adding a New Plugin

1. Create a directory under `plugins/<name>/`
2. Add a `plugin.conf` with `PLUGIN_NAME`, `PLUGIN_DESC`, and `WASM_NAME`
3. Add `install.sh` and `uninstall.sh` scripts in the plugin directory
4. Plugin scripts are `source`d by the root installer; they can use `info`, `success`, `warn`, `error`, `confirm` helpers and the `INSTALL_DIR` env var

## Requirements

- [Zellij](https://zellij.dev/) 0.40+
- `jq` (for automatic configuration during install/uninstall)
