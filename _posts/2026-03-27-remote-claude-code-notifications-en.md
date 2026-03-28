---
title: 'Terminal Notifications for Claude Code in Remote tmux'
date: 2026-03-27
description: 'Get desktop notifications when Claude Code finishes or needs input in remote tmux sessions — using only OSC 777 escape sequences and tmux passthrough, zero dependencies.'
---

I've been using [cmux](https://cmux.com/docs/concepts) (a terminal multiplexer with built-in Claude Code integration) to run multiple Claude Code agents in parallel on my local machine — different projects, different tasks, all pushing forward at the same time. Notifications just work: an agent finishes, I get pinged, I switch over. The whole "agent legion" model hums along nicely.

Then I needed to work on a remote server. I SSH'd in, fired up tmux, started Claude Code — and the notifications stopped. Agent finishes, I don't know. Waiting for input, I don't know. I'm back to polling my terminal like it's 2005.

<!-- more -->

## The Existing Solutions: Powerful but Over-Engineered

After living with this problem for a while, I found a few articles with solutions:

- [Claude Code + Tmux: How I got notifications working](https://software-dc.com/blog/4-claude-code-tmux-how-i-got-notifications-working)
- [Notification System for Tmux and Claude Code](https://quemy.info/2025-08-04-notification-system-tmux-claude.html)

Their approach: Claude Code sends HTTP request → n8n workflow processes it → Gotify pushes notification → local webhook receives it → system notification.

It works. But **it's a lot of machinery for a notification**:

- n8n workflow engine
- Gotify notification server
- Local webhook service
- Docker containers

30+ minutes to set up, plus ongoing maintenance. I just want to know when my agent is done.

## OSC 777: The Notification Protocol Hiding in Your Terminal

Here's the thing: your terminal already supports notifications. It has for years. OSC (Operating System Command) is a terminal escape sequence standard, and OSC 777 is specifically designed for notifications. Your terminal — iTerm2, Ghostty, Kitty, whatever — already knows how to display them.

The only reason it doesn't work through tmux is... tmux. It intercepts escape sequences. But tmux also has a built-in escape hatch: **passthrough mode**.

```
ESC Ptmux ; ESC <OSC sequence> ESC \
```

Wrap your OSC 777 notification in passthrough, and tmux will politely let it through.

### OSC 777 Notification Format

```
ESC ] 777 ; notify ; <title> ; <body> BEL
```

### The entire notification in one line:

```bash
printf '\033Ptmux;\033\033]777;notify;Title;Body\007\033\\'
```

One line. Zero dependencies. No Docker, no webhook, no n8n.

## Complete Implementation

### 1. tmux Configuration

First, tell tmux to allow passthrough:

```bash
# ~/.tmux.conf
set -g allow-passthrough on
set -ga terminal-overrides ',*:allow-passthrough=on'
```

### 2. Create Hook Script

**Key points**:

1. Hook scripts run in the background, so direct `printf` output won't appear in the foreground pane. The solution is to create a temporary pane to send the notification, which then auto-closes.
2. Use `-P` option to prevent `split-window` from resetting the window name.
3. **Important**: Use `-t "$WINDOW_ID"` to specify the target window, otherwise it will incorrectly rename the currently active window.
4. Special characters in notification content (backticks, `$`, etc.) get interpreted by the shell. Solution: write the OSC sequence to a temp file first, then `cat` it in the temporary pane.
5. Use `awk substr` to truncate by characters, not `head -c` which truncates by bytes and can break UTF-8 multi-byte characters.

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
    # Truncate by characters to avoid breaking UTF-8 multi-byte characters
    body=$(echo "$body" | awk '{if(length($0)>100) print substr($0,1,100)"…"; else print}')
    # Escape special characters to prevent shell interpretation
    body=$(echo "$body" | sed "s/'/'\\\\''/g")
    # Write to temp file to avoid shell special character issues
    local tmp=$(mktemp)
    printf '\033Ptmux;\033\033]777;notify;Claude @ tmux:%s;%s\007\033\\' "$LOCATION" "$body" > "$tmp"
    # -P option prevents resetting window name
    tmux split-window -v -l 1 -P "cat '$tmp'; rm -f '$tmp'" 2>/dev/null
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
        # Extract Claude's last response as notification body
        if command -v jq &>/dev/null; then
            LAST_MSG=$(echo "$INPUT" | jq -r '.last_assistant_message // empty' 2>/dev/null | awk '{if(length($0)>80) print substr($0,1,80)"…"; else print}' | head -1)
        else
            LAST_MSG=$(json_extract "$INPUT" "last_assistant_message")
            LAST_MSG=$(echo "$LAST_MSG" | awk '{if(length($0)>80) print substr($0,1,80)"…"; else print}')
        fi
        osc_notify "${LAST_MSG:-$SHORT_PATH ✓}"
        sleep 0.2
        add_bell_indicator
        ;;
    notification|notify)
        if command -v jq &>/dev/null; then
            BODY=$(echo "$INPUT" | jq -r '.body // "Needs input"' 2>/dev/null | awk '{if(length($0)>100) print substr($0,1,100)"…"; else print}')
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

Notifications travel through the SSH connection back to your local terminal, which triggers them as system notifications (iTerm2, Ghostty, cmux, etc.).

## Bring the Agent Legion to Remote Servers

With this notification setup, my remote agents work exactly like my local cmux agents. Each agent runs in its own tmux window, I get pinged when it needs me, and I can run multiple agents in parallel without babysitting any of them.

My typical remote layout: one tmux session per project, multiple tmux sessions connected at once. Inside each session, different windows and panes manage different task groups — one window for the agent doing the main coding, another for the agent running tests, another for monitoring. When any agent across any session finishes, the notification tells me exactly which project and which window needs attention.

**Notifications are the nervous system of the agent legion.** Without them, you're manually polling windows. With them, you context-switch on demand and stay focused on whatever else you're doing.

The `🔔` prefix on tmux window names is a workaround, by the way. Right now cmux can auto-switch to the right tab when a notification comes in, but it can't reach *into* tmux to switch to a specific window. So the bell tells you which window to go to manually. This is a temporary compromise — if cmux adds a hook that fires when you click a notification and land on the tab (so you can run a custom command like `tmux select-window -t bell`), we'd be able to jump directly to the tmux window where Claude Code is waiting for input. Fingers crossed.

One gotcha: **don't run a local Claude Code session in the same cmux workspace.** cmux detects `claude_code` processes and suppresses OSC 777 notifications to avoid duplicating its built-in Claude hook. Your hook script's notifications would be silently dropped. Instead, create a dedicated cmux workspace for SSH connections to your remote server.

## One-Click Setup: Feed This Article to Claude Code

Want this setup on your own machine? The clean markdown version of this article is available here:

**[remote-claude-code-notifications-en.md](/md/remote-claude-code-notifications-en.md)**

Just feed that file to Claude Code and say:

```
Read the article at https://blog.jamespan.tech/md/remote-claude-code-notifications-en.md,
then follow its steps to set up remote Claude Code notifications on my machine:
- Create the hook scripts with the exact code from the article
- Configure tmux passthrough
- Configure Claude Code hooks
```

Claude Code will read the article, create the hook scripts, configure tmux, and set up the hooks — all automatically. Two minutes, zero manual work.

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
