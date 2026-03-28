---
title: 'Remote Claude Code Notifications: Zero-Dependency OSC Passthrough Solution'
date: 2026-03-27
---

If you run Claude Code inside tmux on a remote server, you might encounter a problem: the task finishes, but you don't know about it. Claude Code's notification mechanism only works locally by default, so in remote environments you need to find another way.

<!-- more -->

## Problems with Existing Solutions

After some searching, I found a few articles discussing this issue:

- [Claude Code + Tmux: How I got notifications working](https://software-dc.com/blog/4-claude-code-tmux-how-i-got-notifications-working)
- [Notification System for Tmux and Claude Code](https://quemy.info/2025-08-04-notification-system-tmux-claude.html)

The approach in these solutions is: Claude Code sends HTTP request → n8n workflow processes it → Gotify pushes notification → local webhook receives it → system notification.

Sounds complete, but the problem is: **it's too heavy!** You need:

- n8n workflow engine
- Gotify notification server
- Local webhook service
- Docker containers

The whole setup takes at least 30 minutes, plus ongoing maintenance of these services.

## A Simpler Solution: OSC Passthrough

Actually, terminals themselves support notification mechanisms. OSC (Operating System Command) is a type of terminal escape sequence, and OSC 777 is specifically designed for notifications.

The problem is that tmux intercepts these escape sequences. The solution is to use tmux's passthrough feature to wrap the OSC sequences:

```
ESC Ptmux ; ESC <OSC sequence> ESC \
```

### OSC 777 Notification Format

```
ESC ] 777 ; notify ; <title> ; <body> BEL
```

### Complete bash Implementation

```bash
printf '\033Ptmux;\033\033]777;notify;Title;Body\007\033\\'
```

One line, zero dependencies.

## Complete Implementation

### 1. tmux Configuration

First, ensure tmux allows passthrough:

```bash
# ~/.tmux.conf
set -g allow-passthrough on
set -ga terminal-overrides ',*:allow-passthrough=on'
```

### 2. Create Hook Script

> **Key insights**:
> 1. Hook scripts run in the background, so direct `printf` output won't appear in the foreground pane. The solution is to create a temporary pane to send the notification, which then auto-closes.
> 2. Use `-P` option to prevent `split-window` from resetting the window name.
> 3. **Important**: Use `-t "$WINDOW_ID"` to specify the target window, otherwise it will incorrectly rename the currently active window.

```bash
# ~/.claude/hooks/cmux-remote-notify.sh
#!/bin/bash
[ -n "$TMUX" ] || exit 0

LOCATION=$(tmux display-message -t "$TMUX_PANE" -p '#{session_name}:#{window_index}')
SHORT_PATH=$(tmux display-message -t "$TMUX_PANE" -p '#{pane_current_path}' | sed 's/.*\/\(.*\/.*\)/\1/')
WINDOW_ID=$(tmux display-message -t "$TMUX_PANE" -p '#{window_id}')
WINDOW_NAME=$(tmux display-message -t "$TMUX_PANE" -p '#{window_name}')

osc_notify() {
    local body="${1:-}"
    body="${body:0:100}"
    # -P option prevents resetting window name
    tmux split-window -v -l 1 -P "printf '\033Ptmux;\033\033]777;notify;Claude @ tmux:$LOCATION;$body\007\033\\\\'" 2>/dev/null
}

add_bell_indicator() {
    if [[ ! "$WINDOW_NAME" =~ ^🔔[[:space:]] ]]; then
        # Use -t to specify target window, avoid renaming active window
        tmux rename-window -t "$WINDOW_ID" "🔔 $WINDOW_NAME"
    fi
}

json_extract() {
    local json="$1" key="$2"
    echo "$json" | grep -o "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
        | sed 's/.*: *"\([^"]*\)".*/\1/' | head -1
}

INPUT=$(cat)
EVENT="$1"

case "$EVENT" in
    stop|idle)
        osc_notify "$SHORT_PATH ✓"
        sleep 0.2
        add_bell_indicator
        ;;
    notification|notify)
        if command -v jq &>/dev/null; then
            BODY=$(echo "$INPUT" | jq -r '.body // "Needs input"' 2>/dev/null | head -c 100)
        else
            BODY=$(json_extract "$INPUT" "body")
            [ -z "$BODY" ] && BODY="Needs input"
        fi
        osc_notify "$SHORT_PATH: $BODY"
        sleep 0.2
        add_bell_indicator
        ;;
esac
```

### 3. Setup Auto-clear 🔔

When switching to a window with 🔔, automatically clear it:

```bash
# ~/.claude/hooks/tmux-clear-bell.sh
#!/bin/bash
WIN_NAME=$(tmux display-message -p '#{window_name}')
if [[ "$WIN_NAME" =~ ^🔔[[:space:]] ]]; then
    CLEAN_NAME="${WIN_NAME#🔔 }"
    tmux rename-window "$CLEAN_NAME"
fi
```

```bash
# Enable focus-events and set hook
tmux set-option -g focus-events on
tmux set-hook -g pane-focus-in "run-shell '~/.claude/hooks/tmux-clear-bell.sh'"
chmod +x ~/.claude/hooks/tmux-clear-bell.sh
```

Notification format: `Claude @ tmux:3:1` → `Projects/ruodojo ✓` (title shows location, body shows directory)

Window shows `🔔` prefix, which disappears when you switch to it.

### 4. Configure Claude Code Hooks

```json
// ~/.claude/settings.json
{
  "hooks": {
    "Stop": [{
      "matcher": "",
      "hooks": [{ "type": "command", "command": "~/.claude/hooks/cmux-remote-notify.sh stop" }]
    }],
    "Notification": [{
      "matcher": "",
      "hooks": [{ "type": "command", "command": "~/.claude/hooks/cmux-remote-notify.sh notification" }]
    }]
  }
}
```

### 5. Make Script Executable

```bash
chmod +x ~/.claude/hooks/cmux-remote-notify.sh
```

## How It Works

1. **Claude needs input** → Notification hook triggers → sends notification with message content
2. **Task complete** → Stop hook triggers → sends notification with ✓

Notifications are passed back to your local terminal through the SSH connection, then triggered as system notifications by the terminal (e.g., iTerm2, Ghostty, cmux, etc.).

## Compatibility

This solution depends on:

1. **tmux passthrough** - supported in tmux 2.4+
2. **OSC 777 support** - most modern terminals support it (iTerm2, Ghostty, cmux, Kitty, Alacritty, etc.)

If your terminal doesn't support OSC 777, consider using OSC 9 (Windows Terminal) or OSC 99 (some terminal emulators).

## Comparison with Existing Solutions

| Feature | OSC Passthrough | n8n + Gotify |
|---------|-----------------|--------------|
| Dependencies | None | n8n, Gotify, Docker, webhook |
| Setup time | 2 minutes | 30+ minutes |
| Maintenance | None | Need to maintain multiple services |
| Click to jump | ❌ | ✅ |
| Multi-device | ❌ | ✅ |
| Complexity | Low | High |

## Conclusion

If you just want to receive notifications when remote Claude Code finishes tasks, you don't need to build a complex service stack. tmux passthrough + OSC 777 is enough, done in two minutes.

Of course, if you need to click notifications to jump to specific locations, or push to multiple devices, the n8n solution might be more suitable. But for most scenarios, simple is beautiful.
