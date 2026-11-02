# Agent tasks

[简体中文](AGENT-CONTROL.zh-CN.md)

Use Mac mini Mode with Codex, Claude Code or another MCP client to keep your Mac running during builds, tests and other long jobs. Install Mac mini Mode in `/Applications` first. MCP requires macOS 13 or later.

## Install a plugin

Extract the plugin ZIP into a folder you want to keep. Each plugin includes the MCP executable for Apple silicon and Intel.

For Codex, run these commands from the folder containing `codex`:

```sh
codex plugin marketplace add ./codex
codex plugin add macminimode@macminimode-local
```

Restart Codex after installation, then select MacMiniMode in a chat.

For Claude Code, run these commands from the folder containing `claude-code`:

```sh
claude plugin marketplace add ./claude-code
claude plugin install macminimode@macminimode-local
```

You can also load it for one session with `claude --plugin-dir ./claude-code`.

## How tasks work

Tasks use Automatic by default: the Mac stays awake while plugged in. Ask for Always On to keep a task running on battery. If several tasks are running, Always On takes priority. Finishing the last task switches to Always Off.

The **Agent Tasks** menu shows task names, sources and start times. Tasks stay registered if a client quits or loses its connection; end leftover tasks from this menu. Selecting any mode manually clears all tasks and applies your selection. **Quit and Allow Sleep** also clears the tasks.

Low-battery settings apply to agent tasks too. When protection activates, Always On tasks switch to Automatic. The recovery setting controls whether they return to Always On after charging.

## Low-battery settings

Open **Settings…** from the menu. Enable low-battery switching and choose a threshold from 10% to 50% (default 20%). While running on battery in Always On, reaching this level switches the mode to Automatic.

Choose **Keep Automatic** or **Restore previous Always On**. Restoration happens when you plug in the power adapter or the battery reaches five percentage points above the threshold. Changing the mode or settings cancels pending restoration.

This setting is off by default. With it off, the original protection allows sleep at 10% and restores operation at 15% or when plugged in. Settings are saved by the background service.

## Other MCP clients

Instead of installing a plugin, add this server to your client's MCP configuration:

```json
{
  "mcpServers": {
    "macminimode": {
      "command": "/Applications/MacMiniMode.app/Contents/MacOS/macminimode-mcp",
      "args": []
    }
  }
}
```

| Tool | What it does |
| --- | --- |
| `get_status` | Reads the mode, sleep prevention, power source, battery, tasks and low-battery settings. |
| `begin_task` | Starts a task with a unique `id`, a short `name`, a `source` and an optional `mode` (`auto` or `on`). |
| `end_task` | Ends the task matching `id`. Repeated calls are supported. |
| `set_mode` | Clears tasks and selects `auto`, `on` or `off`. |

Keep the same task ID when retrying a request. Responses include `saved` for persistence and `applied` for the system result. Automatic on battery allows sleep even when `applied` is true. Task timestamps use ISO 8601 UTC.

## Command line

```sh
macminimode status --json
macminimode task begin UUID "Build project" "Script" auto
macminimode task end UUID
```

Replace `UUID` with a fresh task identifier. The existing `macminimode auto|on|off` commands act like selecting a mode from the menu.

## Remove a plugin

```sh
codex plugin remove macminimode@macminimode-local
# or
claude plugin uninstall macminimode@macminimode-local
```

End any remaining tasks from **Agent Tasks** in the menu.

## Build from source

```sh
bash scripts/build.sh
bash scripts/package-plugins.sh
```

The installer and plugin ZIPs are written to `build/`. The MCP package uses the official Swift SDK, with dependencies pinned in `MCP/Package.resolved`.

To run the tests:

```sh
bash scripts/test-control.sh
bash scripts/test-quit.sh
swift test --package-path MCP
swift build --package-path MCP -c release --force-resolved-versions
python3 Tests/mcp_integration.py
```

The integration tests run against a temporary service with simulated power readings.
