<p align="center">
  <img src="ClaudeOmator/ClaudeOmator.icon/Assets/icon.png" width="128" alt="ClaudeOmator icon" />
</p>

<h1 align="center">ClaudeOmator</h1>

<p align="center">
  A macOS menu bar app that runs Claude Code workflows on autopilot.
</p>

---

Define a prompt, point it at a directory, set a schedule, and let Claude do the
work. ClaudeOmator talks to the [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code)
directly through the [ClaudeCodeSDK](https://github.com/jamesrochabrun/ClaudeCodeSDK),
streams output in real time, and sends you a notification when it's done.

## Features

- **Scheduled workflows** built on `Calendar.RecurrenceRule` (minutely, hourly,
  daily, weekly, monthly, yearly, or manual)
- **Live streaming output** so you can watch Claude think
- **Menu bar quick access** to run, stop, and monitor workflows without opening
  the main window
- **Session resume** opens your terminal and drops you right back into the
  Claude conversation
- **Workflow groups** to keep things organized
- **Activity history** with per-run output, status, and error details
- **Configurable model and permission mode** per workflow (default, plan, auto)
- **macOS notifications** on completion

## Download

Grab the latest build from
[Releases](https://github.com/lukasmalkmus/ClaudeOmator/releases/latest).
The app is unsigned, so right-click and select **Open** to bypass Gatekeeper on
first launch.

## Requirements

- macOS 26.2+
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed
  and authenticated
- Xcode 26.3+ (to build from source)

## Build from Source

Clone the repo and build with Xcode:

```
git clone https://github.com/lukasmalkmus/ClaudeOmator.git
cd ClaudeOmator
open ClaudeOmator.xcodeproj
```

Build and run the **ClaudeOmator** scheme. The app lives in your menu bar.

## Usage

1. Create a workflow and give it a name
2. Write a prompt (what you want Claude to do)
3. Pick a working directory (the repo or folder Claude operates in)
4. Optionally set a schedule, model, and permission mode
5. Hit **Run**

Output streams live into the app. When the run finishes, click **Resume in
Terminal** to continue the conversation in Claude Code.

## License

[MIT](LICENSE)
