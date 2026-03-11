<p align="center">
  <img src="ClaudeOmator/ClaudeOmator.icon/Assets/icon.png" width="200" alt="ClaudeOmator icon" />
</p>

<h1 align="center">ClaudeOmator</h1>

<p align="center">
  A macOS menu bar app that runs Claude Code workflows on autopilot.
</p>

Define a prompt, point it at a directory, set a schedule, and let Claude do the
work. ClaudeOmator talks to the [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code)
directly through the [ClaudeCodeSDK](https://github.com/jamesrochabrun/ClaudeCodeSDK)
and sends you a notification when it's done.

## Features

- **Scheduled workflows** on any cadence (minutely to yearly, or manual)
- **Menu bar quick access** to run, stop, and monitor workflows
- **Session resume** drops you right back into the Claude conversation in your terminal
- **Configurable model and permission mode** per workflow (default, plan, auto)
- **Workflow groups** and **activity history** to stay organized
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

When the run finishes, click **Resume in Terminal** to continue the conversation
in Claude Code.

## License

[MIT](LICENSE)
