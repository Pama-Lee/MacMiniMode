---
name: macminimode
description: Keep a local Mac available during long builds, tests, batch processing or other long-running work using MacMiniMode. Use when such work benefits from preventing sleep, or the user asks to inspect or change MacMiniMode.
---

# MacMiniMode task control

Use the bundled MacMiniMode MCP tools on the local Mac. Requires the matching MacMiniMode app and service installed, and macOS 13 or newer. If unavailable, report this without claiming protection is active.

1. Call `get_status` before long work. Ordinary questions and short operations do not need a registration.
2. Generate a fresh UUID task id, retain it in working context, and call `begin_task` with a concise non-sensitive name, source Claude Code, and `mode: auto`. Automatic prevents sleep ONLY on AC power. Use `mode: on` only if the user explicitly requests work to continue on battery. Do not bypass low-battery policy.
3. Confirm `ok`, `saved`, `applied`, actual `sleepDisabled`, and any protection reason. On battery, auto may be successfully applied while sleep prevention is off; explain that distinction. A failed reply may still have saved a registration: query status, retry with the SAME id, or release that id if abandoning work. Do not create duplicate registrations after a timeout.
4. Keep the id while this task and its associated background processes are running. Context compaction is not task completion. Do not release merely because a command returned a background process id.
5. Call `end_task` with your id when all work completes, fails, or is cancelled. Also release before waiting for user input if no background work remains. Never end another task. If protection was manually cleared, do not re-register unless the user asks to continue with protection.
6. The last task release selects Always Off and can sleep a closed laptop. Save outputs and complete required work before release. Query status if the response is missing; repeating end_task is safe.

Registrations survive disconnection and crashes. There is no timed expiry. If cleanup could not run, tell the user to use Agent Tasks in the menu or explicitly ask an agent to release the old id. Plugin uninstall does not clear registrations.

Use `set_mode` only for an explicit user mode-change instruction. It clears ALL registrations and overrides other tasks. Never use it for ordinary cleanup. Native low-battery preferences are configured in Settings, not modified through MCP. Do not install packages, change client settings, or publish anything merely to use these tools.
