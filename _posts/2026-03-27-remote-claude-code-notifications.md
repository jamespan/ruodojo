---
title: '远程 Claude Code 通知：零依赖的 OSC Passthrough 方案'
date: 2026-03-27
---

如果你在远程服务器的 tmux 里运行 Claude Code，可能会遇到一个问题：任务完成了，但你不知道。Claude Code 的通知机制默认只能在本地工作，远程环境下你需要另想办法。

<!-- more -->

## 现有方案的问题

搜索了一下，发现已经有几篇文章讨论这个问题：

- [Claude Code + Tmux: How I got notifications working](https://software-dc.com/blog/4-claude-code-tmux-how-i-got-notifications-working)
- [Notification System for Tmux and Claude Code](https://quemy.info/2025-08-04-notification-system-tmux-claude.html)

这些方案的思路是：Claude Code 发送 HTTP 请求 → n8n 工作流处理 → Gotify 推送通知 → 本地 webhook 接收 → 系统通知。

听起来很完整，但问题是：**太重了！** 你需要：

- n8n 工作流引擎
- Gotify 通知服务器
- 本地 webhook 服务
- Docker 容器

整套下来至少 30 分钟，还得维护这些服务。

## 更简单的方案：OSC Passthrough

其实，终端本身就支持通知机制。OSC（Operating System Command）是终端转义序列的一种，其中 OSC 777 就是专门用于通知的。

问题在于，tmux 会拦截这些转义序列。解决方案是使用 tmux 的 passthrough 功能，把 OSC 序列包装起来：

```
ESC Ptmux ; ESC <OSC sequence> ESC \
```

### OSC 777 通知格式

```
ESC ] 777 ; notify ; <title> ; <body> BEL
```

### 完整的 bash 实现

```bash
printf '\033Ptmux;\033\033]777;notify;Title;Body\007\033\\'
```

一行命令，零依赖。

## 完整实现

### 1. tmux 配置

首先确保 tmux 允许 passthrough：

```bash
# ~/.tmux.conf
set -g allow-passthrough on
set -ga terminal-overrides ',*:allow-passthrough=on'
```

### 2. 创建 hook 脚本

> **关键点**：
> 1. hook 脚本在后台运行，直接 `printf` 输出不会显示在前台 pane。解决方案是新建一个临时 pane 发送通知，然后自动关闭。
> 2. 使用 `-P` 选项避免 `split-window` 重置 window 名字。
> 3. **重要**：使用 `-t "$WINDOW_ID"` 指定目标 window，否则会错误地重命名当前激活的 window。

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
    # -P 选项避免重置 window 名字
    tmux split-window -v -l 1 -P "printf '\033Ptmux;\033\033]777;notify;Claude @ tmux:$LOCATION;$body\007\033\\\\'" 2>/dev/null
}

add_bell_indicator() {
    if [[ ! "$WINDOW_NAME" =~ ^🔔[[:space:]] ]]; then
        # 使用 -t 指定目标 window，避免重命名激活的 window
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

### 3. 设置 🔔 自动清除

当切换到有 🔔 的 window 时，自动清除标识：

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
# 确保 focus-events 开启，并设置 hook
tmux set-option -g focus-events on
tmux set-hook -g pane-focus-in "run-shell '~/.claude/hooks/tmux-clear-bell.sh'"
chmod +x ~/.claude/hooks/tmux-clear-bell.sh
```

通知格式：`Claude @ tmux:3:1` → `Projects/ruodojo ✓`（标题显示位置，正文显示目录）

window 会显示 `🔔` 前缀，切换到该 window 后自动消失。

### 4. 配置 Claude Code hooks

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

### 5. 给脚本执行权限

```bash
chmod +x ~/.claude/hooks/cmux-remote-notify.sh
```

## 工作原理

1. **Claude 需要输入** → Notification hook 触发 → 发送包含消息内容的通知
2. **任务完成** → Stop hook 触发 → 发送带 ✓ 的通知

通知通过 SSH 连接传回本地终端，再由终端（如 iTerm2、Ghostty、cmux 等）触发系统通知。

## 兼容性

这个方案依赖：

1. **tmux passthrough** - tmux 2.4+ 支持
2. **OSC 777 支持** - 大多数现代终端都支持（iTerm2、Ghostty、cmux、Kitty、Alacritty 等）

如果你的终端不支持 OSC 777，可以考虑用 OSC 9（Windows Terminal）或 OSC 99（一些终端模拟器）。

## 与现有方案对比

| 特性 | OSC Passthrough | n8n + Gotify |
|------|-----------------|--------------|
| 依赖 | 无 | n8n, Gotify, Docker, webhook |
| 设置时间 | 2 分钟 | 30+ 分钟 |
| 维护成本 | 无 | 需要维护多个服务 |
| 点击跳转 | ❌ | ✅ |
| 多设备 | ❌ | ✅ |
| 复杂度 | 低 | 高 |

## 总结

如果你只是想在远程 Claude Code 完成任务时收到通知，不需要搭建复杂的服务栈。tmux passthrough + OSC 777 就够了，两分钟搞定。

当然，如果你需要点击通知跳转到具体位置，或者需要推送到多个设备，那 n8n 方案可能更适合。但对于大多数场景，简单就是美。
