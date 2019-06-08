---
title: Pastime
featured_image: 'https://ws3.sinaimg.cn/large/006tNbRwly1fxaxjiumpwj318z0u0at2.jpg'
---

<div class="gallery" data-columns="4">
    {% for exhibition in site.data.flows.pastime limit: 20 %}
        <img src="{{ exhibition.img }}">
    {% endfor %}
</div>

<p>
    <a href="/pastime-archive" class="button">Read More</a>
</p>
