# Codex Monitor

A native macOS menu bar app that shows what Codex is doing without keeping the Codex window open.

## Install with Codex

Paste this into Codex:

```text
Install https://github.com/EpirusYUE/codex-menu-bar-monitor
```

Codex should clone the repository and run:

```bash
./scripts/install.sh
```

The installer builds the app locally, installs it as `~/Applications/Codex Monitor.app`, and launches it. No administrator password is required.

## Features

- Always shows the preferred remaining Codex quota: the 5-hour window when available, otherwise the weekly window.
- Draws a smooth white light trail around the quota badge while Codex is working.
- Shows the number of active tasks in a blue badge.
- Flashes once for every completed task, including multiple completions between status checks.
- Optionally sends an iPhone push notification for every completed task through ntfy.
- Stops immediately for interrupted tasks without showing a completion flash.
- Keeps the last known quota visible when Codex has been idle or its status is temporarily unavailable.
- Provides a menu for active tasks, manual refresh, opening Codex, and testing the completion flash.

## Privacy

Codex Monitor is read-only. It reads Codex lifecycle events from `~/.codex/state_5.sqlite` and local rollout files, and queries the bundled Codex app-server for rate-limit information. It does not modify Codex data or send task content anywhere.

## Requirements

- macOS 13 or later
- ChatGPT installed at `/Applications/ChatGPT.app` (legacy `/Applications/Codex.app` is also supported)
- Xcode Command Line Tools

Install the command-line tools if needed:

```bash
xcode-select --install
```

## iPhone notifications

1. Install `ntfy` from the iOS App Store.
2. Open the Codex Monitor menu and choose **复制 iPhone 订阅地址** (Copy iPhone Subscription URL).
3. Add that URL as a subscription in the ntfy app.
4. Enable **iPhone 通知** (iPhone Notifications) in the Codex Monitor menu.
5. Choose **发送 iPhone 测试消息** (Send iPhone Test Notification) to verify delivery.

The generated ntfy topic is random and notifications are disabled until you enable them.

## Build manually

```bash
./scripts/build-app.sh
open "outputs/Codex Monitor.app"
```

Check detected task and quota state from Terminal:

```bash
"outputs/Codex Monitor.app/Contents/MacOS/CodexMenuBar" --status
"outputs/Codex Monitor.app/Contents/MacOS/CodexMenuBar" --quota
```

## Uninstall

```bash
pkill -x CodexMenuBar 2>/dev/null || true
rm -rf "$HOME/Applications/Codex Monitor.app"
```
