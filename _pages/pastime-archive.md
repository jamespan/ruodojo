---
title: 消愁
featured_image: 'https://ws3.sinaimg.cn/large/006tNbRwly1fxaxjiumpwj318z0u0at2.jpg'
---

<style type="text/css">
    .hexo-img-stream-lazy {display:block;}.hexo-img-stream{width:100%;margin:3% auto}div.hexo-img-stream figure{background:#fefefe;box-shadow:0 1px 2px rgba(34,25,25,0.4);margin:0 0.05% 3%;padding:3%;padding-bottom:10px;display:inline-block;max-width:24%}div.hexo-img-stream figure img{border-bottom:1px solid #ccc;padding-bottom:15px;margin-bottom:5px}div.hexo-img-stream figure figcaption{font-size:.9rem;color:#444;line-height:1.5;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;}div.hexo-img-stream small{font-size:1rem;float:right;text-transform:uppercase;color:#aaa}div.hexo-img-stream small a{color:#666;text-decoration:none;transition:.4s color}@media screen and (max-width:750px){.hexo-img-stream{column-gap:0}}
</style>

<div class="hexo-img-stream">
    {% for exhibition in site.data.flows.pastime %}
        <figure>
            <img class="hexo-img-stream-lazy" src="{{ exhibition.img }}">
            <noscript><img src="{{ exhibition.img }}"></noscript>
            <figcaption>
                <a href="{{ exhibition.url }}" target="_blank">{{ exhibition.title }}</a>
            </figcaption>
        </figure>
    {% endfor %}
    {% for exhibition in site.data.flows_archive.pastime %}
        <figure>
            <img class="hexo-img-stream-lazy" src="{{ exhibition.img }}">
            <noscript><img src="{{ exhibition.img }}"></noscript>
            <figcaption>
                <a href="{{ exhibition.url }}" target="_blank">{{ exhibition.title }}</a>
            </figcaption>
        </figure>
    {% endfor %}
</div>

<script src="https://ajax.lug.ustc.edu.cn/ajax/libs/jquery/3.2.1/jquery.min.js"></script>
<script type="text/javascript">
$(function() {
  if (window.location.hash) {
    do {
      var mapping = {
        'book': ['book.douban.com', 'www.oreilly.com', 'www.amazon.cn'],
        'movie': ['movie.douban.com'],
      }
      var filter = window.location.hash.substring(1);
      var domains = mapping[filter];
      if (domains == null) {
        break;
      }
      $('figure').each(function(i) {
        var url = $(this).find('a')[0].href;
        var hostname = (new URL(url)).hostname;
        if ($.inArray(hostname, domains) < 0) {
          $(this).remove();
        }
      });
    } while(false);
  } 
});
</script>
