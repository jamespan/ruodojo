---
title: 销愁
featured_image: 'https://ws3.sinaimg.cn/large/006tNbRwly1fxaxjiumpwj318z0u0at2.jpg'
---

<div class="gallery" data-columns="4">
    {% for exhibition in site.data.flows.pastime limit: 12 %}
        <img src="{{ exhibition.img | replace: 'bmiddle', 'large' }}">
    {% endfor %}
</div>

[Show More](/pastime-archive){:class="button"}
