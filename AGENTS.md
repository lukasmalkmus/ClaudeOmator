# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

ClaudeOmator is a macOS application for automating Claude interactions. Built with SwiftUI.

- **Bundle ID:** com.lukasmalkmus.ClaudeOmator
- **Deployment Target:** macOS 26.2
- **Swift:** 6 (Approachable Concurrency, MainActor default isolation)

## Build & Run

Xcode's native MCP server is configured (`.mcp.json`). Use its tools directly:
`BuildProject`, `GetBuildLog`, `RunAllTests`, `RenderPreview`, etc.

Xcode must be running with the project open. Enable in:
Xcode > Settings > Intelligence > Model Context Protocol > Xcode Tools

```bash
# Manual alternative:
xcodebuild -project ClaudeOmator.xcodeproj -scheme ClaudeOmator build
```

- **Scheme:** ClaudeOmator

## Install & Test

After building, install to `/Applications` and relaunch to test the real app.

**ClaudeOmator is a login item.** macOS auto-relaunches it after `pkill`. Use
`osascript -e 'quit app "ClaudeOmator"'` for a graceful quit that persists data
and does not trigger auto-relaunch:

```bash
osascript -e 'quit app "ClaudeOmator"' 2>/dev/null
sleep 1
xcodebuild -project ClaudeOmator.xcodeproj -scheme ClaudeOmator -configuration Release \
  -derivedDataPath /tmp/ClaudeOmator-build build
trash /Applications/ClaudeOmator.app
cp -R /tmp/ClaudeOmator-build/Build/Products/Release/ClaudeOmator.app /Applications/
open /Applications/ClaudeOmator.app
```

**Do NOT use `pkill -9`.** SIGKILL skips `willTerminateNotification` (data not saved)
and macOS immediately re-spawns the login item, creating a race where the old instance
overwrites `workflows.json` with empty state before the new binary is in place.

The app enforces single-instance via bundle ID check in
`AppDelegate.ensureSingleInstance()`. A duplicate will activate the existing instance
and terminate itself.

## UI Feedback Loop

Views have `#Preview` macros. Use `mcp__xcode__RenderPreview` to verify UI changes
visually before presenting to user. Preview data uses `WorkflowStore.preview()` (DEBUG only).

## Gotchas

- **MenuBarExtra** does NOT propagate `@Environment` for `@Observable` objects.
  Pass dependencies directly as properties (e.g. `NavigationState` to `MenuBarView`).
- **Previews crash when ClaudeOmator is running.** Kill the running instance before
  using `RenderPreview`. The single-instance guard in `AppDelegate` causes the preview
  host to detect the running app and terminate itself.
- **`Calendar.RecurrenceRule.recurrences(of:in:)` is Beta (macOS 26)** and hangs
  indefinitely for monthly rules using `.nth` ordinal weekdays (e.g. "1st Monday").
  `nextFireDate(after:)` in `Workflow.swift` has a workaround that computes ordinal
  weekday dates manually via `Calendar.date(from:)`. Once `recurrences(of:in:)` ships
  as stable, remove the workaround and test `.nth` rules directly.
  Ref: https://developer.apple.com/documentation/foundation/calendar/recurrencerule/recurrences(of:in:)-8l967
