---
title: '远程 Claude Code 通知：零依赖的 OSC Passthrough 方案'
date: 2026-03-27
---

我一直在用 [cmux](https://cmux.com/zh-CN/docs/concepts) 在本地并行跑多个 Claude Code Agent——不同的项目、不同的任务，同时推进。cmux 对 Claude Code 有原生集成，通知开箱即用：Agent 完成了，我收到通知，切过去看一眼。整个"Agent 军团"的模式跑得很顺。

后来工作需要在远程服务器上开发。我 SSH 上去，开了 tmux，启动 Claude Code——通知没了。Agent 完成了，我不知道。等待输入了，我不知道。又回到了盯着终端轮询的时代。

<!-- more -->

## 现有方案：能用，但太重了

跟这个问题纠缠了一阵之后，我找到了几篇讨论这个问题的文章：

- [Claude Code + Tmux: How I got notifications working](https://software-dc.com/blog/4-claude-code-tmux-how-i-got-notifications-working)
- [Notification System for Tmux and Claude Code](https://quemy.info/2025-08-04-notification-system-tmux-claude.html)

他们的思路是：Claude Code 发送 HTTP 请求 → n8n 工作流处理 → Gotify 推送通知 → 本地 webhook 接收 → 系统通知。

能用。但**发个通知而已，这阵容也太豪华了**：

- n8n 工作流引擎
- Gotify 通知服务器
- 本地 webhook 服务
- Docker 容器

整套下来至少 30 分钟，还得持续维护。我只是想知道 Agent 干完了没啊。

## OSC 777：藏在你终端里的通知协议

有意思的是，你的终端早就支持通知了，好多年了。OSC（Operating System Command）是终端转义序列标准，其中 OSC 777 就是专门用来发通知的。你的终端——iTerm2、Ghostty、Kitty，随便哪个——早就知道怎么显示它们。

唯一不工作是因为 tmux。它拦截了转义序列。但 tmux 也留了后门：**passthrough 模式**。

```
ESC Ptmux ; ESC <OSC sequence> ESC \
```

把 OSC 777 通知用 passthrough 包装一下，tmux 就会乖乖放行。

### OSC 777 通知格式

```
ESC ] 777 ; notify ; <title> ; <body> BEL
```

### 一行代码搞定通知：

```bash
printf '\033Ptmux;\033\033]777;notify;Title;Body\007\033\\'
```

一行。零依赖。不用 Docker，不用 webhook，不用 n8n。

## 完整实现

### 1. tmux 配置

首先告诉 tmux 允许 passthrough：

```bash
# ~/.tmux.conf
set -g allow-passthrough on
set -ga terminal-overrides ',*:allow-passthrough=on'
```

### 2. 创建 hook 脚本

**关键点**：

1. hook 脚本在后台运行，直接 `printf` 输出不会显示在前台 pane。解决方案是新建一个临时 pane 发送通知，然后自动关闭。
2. 使用 `-P` 选项避免 `split-window` 重置 window 名字。
3. **重要**：使用 `-t "$WINDOW_ID"` 指定目标 window，否则会错误地重命名当前激活的 window。
4. 通知内容中的特殊字符（反引号、`$` 等）会被 shell 解释。解决方案是先写入临时文件，再在临时 pane 中 `cat` 该文件。
5. 用 `awk substr` 按字符截断，而非 `head -c` 按字节截断，避免破坏 UTF-8 多字节字符。

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
    # 按字符截断，避免截断 UTF-8 多字节字符
    body=$(echo "$body" | awk '{if(length($0)>100) print substr($0,1,100)"…"; else print}')
    # 转义特殊字符，防止 shell 解释
    body=$(echo "$body" | sed "s/'/'\\\\''/g")
    # 写入临时文件，避免 shell 特殊字符问题
    local tmp=$(mktemp)
    printf '\033Ptmux;\033\033]777;notify;Claude @ tmux:%s;%s\007\033\\' "$LOCATION" "$body" > "$tmp"
    # -P 选项避免重置 window 名字
    tmux split-window -v -l 1 -P "cat '$tmp'; rm -f '$tmp'" 2>/dev/null
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
        # 提取 Claude 最后回复的内容作为通知 body
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

## 把 Agent 军团搬到远程服务器

有了这套通知方案，远程 Agent 的体验和本地 cmux 一模一样。每个 Agent 在独立的 tmux window 里跑，需要我的时候通知我，我可以并行跑多个 Agent 而不用盯着任何一个。

我典型的远程布局：一个 tmux 会话对应一个项目，同时连接多个 tmux 会话。每个会话内部用不同的 window 和 pane 管理不同的任务组合——一个 window 放主力的编码 Agent，一个跑测试，一个做监控。无论哪个会话的哪个 Agent 完成，通知都会告诉我具体是哪个项目、哪个 window 需要关注。

**通知是 Agent 军团的神经系统。** 没有通知，你得手动轮询每个窗口；有了通知，你可以按需切换上下文，其他时间专注做别的事。

顺便说一下，tmux window 名字前面的 `🔔` 是个权宜之计。目前 cmux 收到通知后能自动切换到对应的 cmux tab，但没法进一步深入 tmux 内部跳转到具体的 window。所以用铃铛来提示你需要手动切到哪个 window。如果后续 cmux 加一个点击通知跳转到 tab 之后执行自定义操作的 hook（比如自动执行 `tmux select-window -t bell`），就能直接跳转到等待输入的 Claude Code 所在的 tmux window 了。期待那一天。

有一个坑要注意：**不要在远程 tmux 所在的 cmux workspace 里启动本地 Claude Code。** cmux 会检测当前 tab 是否有 `claude_code` 进程，如果有，会抑制所有 OSC 777 通知（避免与自带的 Claude hook 通知重复）。这会导致你的 hook 脚本发出的通知被静默丢弃。正确做法：在 cmux 中建一个专门的 workspace 用来 SSH 到远程服务器。

## 一键配置：把这篇文章喂给 Claude Code

想要在自己的机器上配置同样的方案？本文的干净 Markdown 版本在这里：

**[remote-claude-code-notifications.md](/md/remote-claude-code-notifications.md)**

把这个文件喂给 Claude Code，然后说：

```
按照这篇文章的步骤，帮我配置远程 Claude Code 通知。
https://blog.jamespan.tech/md/remote-claude-code-notifications.md
```

Claude Code 会读取文章，创建 hook 脚本，配置 tmux，设置 hooks——全自动。两分钟，零手动操作。

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
