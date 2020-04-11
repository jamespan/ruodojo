---
title: '懒人翻书不动手'
date: 2020-04-11
featured_image: 'https://tva1.sinaimg.cn/large/0082zybply1gbo8ahd6awj30w90i50tr.jpg'
---

今天在 Macbook 上看 PDF，突然懒癌发作，不想动手翻页。想到 AppleScript 似乎可以做一些 GUI 的自动化，是不是可以每隔一段时间，就帮我划一下触摸板，把书往上翻一翻呢？

<!-- more -->

事实证明我想多了。AppleScript 不支持模拟触摸板操作。那就退而求其次吧，每隔一会自动按一下键盘的向下翻页。

参考 StackOverflow 上一个好心人的[答案][1]，改改应用名称和[按键值][2]，写出了第一版。

```
tell application "System Events"
    repeat while (exists of application process "Preview")
        set activeApp to name of first application process whose frontmost is true
        if "Preview" is in activeApp then
            tell its application process "Preview"
                repeat while frontmost
                    key code 125
                    delay 30
                end repeat
            end tell
        end if
    end repeat
end tell
```

这样就能在 Preview 窗口活动的情况下，每半分钟自动往下翻翻。

我就这么用了一小会之后，感觉不太方便，Preview 不活动的时候，它就不翻书了，很不人性化，我需要多任务，在使用其他 App 的同时，Preview 也在自动翻书。

研究了一会，实现了多个 App 窗口先后激活，先激活 Preview，再翻书，最后激活之前的窗口。

除了切换窗口那一瞬间的闪烁，堪称完美。

```
repeat
	tell application "System Events"
		set appRunning to exists of application process "Preview"
	end tell
	if not appRunning then
		exit repeat
	end if
	delay 30
	tell application "Preview"
		if frontmost then
			set activeApp to "Preview"
		else
			tell application "System Events"
				set activeApp to name of first application process whose frontmost is true
			end tell
		end if
		activate
		tell application "System Events" to key code 125
		log "Next Page"
	end tell
	tell application activeApp
		activate
	end tell
end repeat
```

脚本不识字，何故乱翻书^-^

[1]: https://stackoverflow.com/questions/60268384/macos-send-keystroke-to-the-active-app-periodically
[2]: https://eastmanreference.com/complete-list-of-applescript-key-codes