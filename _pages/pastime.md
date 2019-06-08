---
title: Pastime
featured_image: 'https://ws3.sinaimg.cn/large/006tNbRwly1fxaxjiumpwj318z0u0at2.jpg'
---

我的能力就这么多。我若全心工作，则必然忽略生活；我若用心生活，则必然一事无成；我若两者兼顾，又难免平庸

<div class="gallery" data-columns="4">
    {% for exhibition in site.data.flows.pastime limit: 20 %}
        <img src="{{ exhibition.img }}">
    {% endfor %}
</div>

<p>
    <a href="/pastime-archive" class="button">Read More</a>
</p>
