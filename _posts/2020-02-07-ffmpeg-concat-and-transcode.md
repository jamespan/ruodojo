---
title: '使用 ffmpeg 进行视频合并和转码'
date: 2020-02-07
featured_image: 'https://tva1.sinaimg.cn/large/0082zybply1gbo8ahd6awj30w90i50tr.jpg'
---

这些日子，我们因为 2019-nCov 都躲在家里不敢出门。有一次说起躲避灾难，夫人说我们是不是该一起看看 B站 上的一个求生视频。这部系列视频看起来不错，我决定把它抓下来保存。

<!-- more -->

视频用 Downie 抓下来之后是分片的。

![](https://tva1.sinaimg.cn/large/0082zybply1gbo79k8g2yj324k09kgsq.jpg)

我记得之前用 Downie 下载 B站 动漫的时候不这样啊……我得像个办法把它们合并起来。

批量处理视频，当然得用 ffmepg。由于我这电脑刚装的 macOS 10.15，不太愿意用 brew 装一些有的没的，这次我打算用 docker 来安装一个能用的 ffmpeg。

一番审查， 我选择了 `jrottenberg/ffmpeg:4.1-alpine`，然后就是尝试合并文件啦~

先 touch 一个 files.txt 来放要合并的文件列表，文件名中的空格要转义。

```
file 毒气攻击\ [1\ -\ 7].flv
file 毒气攻击\ [2\ -\ 7].flv
file 毒气攻击\ [3\ -\ 7].flv
file 毒气攻击\ [4\ -\ 7].flv
file 毒气攻击\ [5\ -\ 7].flv
file 毒气攻击\ [6\ -\ 7].flv
file 毒气攻击\ [7\ -\ 7].flv
```

然后用 docker 把命令跑起来。

```
docker run -it --rm -v `pwd`:/space jrottenberg/ffmpeg:4.1-alpine -f concat -safe 0 -i /space/files.txt -c copy /space/10-毒气攻击.flv
```

合并之后，我又想着能不能转码成 mp4，这样才能用苹果新出的 Videos 管理。

```
docker run -it --rm -v `pwd`:/space jrottenberg/ffmpeg:4.1-alpine -i /space/10-毒气攻击.flv /space/10-毒气攻击.mp4
```

用列编辑写了个转码脚本挨个慢慢转。转码是真的慢。

