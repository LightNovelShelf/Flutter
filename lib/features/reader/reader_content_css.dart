/// 书源正文自带的预设类名样式，与 Web 端 `Web/src/css/read.scss` 一份语义
/// （`.illus`/`.duokan-*`/`.emNN`/对齐/着重号等）。书是按这套类名排版的，
/// 阅读器不注入就会丢插图居中、字号缩放、着重号等效果。
///
/// 与阅读设置冲突的两条（`p` 的 `line-height` / `text-indent`）不搬：
/// 那两项由 `--nv-line` / `--nv-indent` 控制。类选择器优先级高于基础 `p`
/// 规则，所以本表必须拼在基础排版之后。
library;

/// `.em05`–`.em30`（`.em10` 不存在，1em 即默认字号）。
final String _fontScaleCss = <String>[
  for (var step = 5; step <= 30; step++)
    if (step != 10)
      '.em${step < 10 ? '0$step' : '$step'}{font-size:${step / 10}em}',
].join();

final String readerContentCss =
    // 插图容器：多图并排居中，可预览的图给边框与投影。
    '.illus,.illu,.duokan-image-single{display:flex;justify-content:center;'
    'flex-wrap:wrap;align-items:center;gap:2px}'
    '.illus img:not(.no-preview),.illu img:not(.no-preview),'
    '.duokan-image-single img:not(.no-preview){box-shadow:black 0 0 3px;'
    'box-sizing:border-box;border:1px solid #ddd;cursor:pointer}'
    'p img{margin:0 5px}'
    'img{border-radius:3px}'
    // 脚注标记。
    'img.footnote{display:inline-block}'
    'a.duokan-footnote{cursor:pointer}'
    'a.duokan-footnote img{height:1em;vertical-align:text-top}'
    'sup{vertical-align:text-top}'
    // 标题。
    '.pius1,.ph4,.pius2,h4{font-size:1.5em;font-weight:bold;'
    'text-indent:1.333em;margin:.5em 0 1em 0}'
    'h1{font-size:1.65em;line-height:120%;text-align:center;font-weight:bold;'
    'margin-top:.1em;margin-bottom:.4em}'
    'h2{font-size:1.25em;line-height:120%;text-align:center;font-weight:bold;'
    'margin-top:.3em;margin-bottom:.5em}'
    'h3{font-size:.95em;line-height:120%;text-align:center;text-indent:0;'
    'font-weight:bold;margin-top:.2em;margin-bottom:.2em}'
    '$_fontScaleCss'
    // 预设排版。
    '.right{text-indent:0;text-align:right}'
    '.left{text-indent:0;text-align:left}'
    '.center{text-indent:0;text-align:center}'
    '.zin{text-indent:0}'
    '.bold{font-weight:bold}'
    '.ita{font-style:italic}'
    '.stress{font-weight:bold;font-size:1.1em;margin-top:.3em;'
    'margin-bottom:.3em}'
    '.author{font-size:1.2em;text-align:right;font-weight:bold;'
    'font-style:italic;margin-right:1em}'
    '.dash-break{word-break:break-all;word-wrap:break-word}'
    '.no-d{text-decoration:none}'
    '.bc{border-collapse:collapse}'
    '.message,.cut-line{text-indent:0;line-height:1.2em;margin-top:.2em;'
    'margin-bottom:.2em}'
    '.meg{font-size:1.3em;line-height:1.3em;margin:.5em 0 0 0;text-indent:0}'
    '.lh{line-height:1em}'
    '.m0{margin:0}'
    '.p0{padding:0}'
    // 颜色。
    '.red{color:#ff0000}'
    '.green{color:#00ff00}'
    '.blue{color:#0000ff}'
    '.black{color:#000000}'
    '.white{color:#ffffff}'
    // 浮动与垂直对齐。
    '.fl{float:left}'
    '.fr{float:right}'
    '.cl{clear:left}'
    '.cr{clear:right}'
    '.cb{clear:both}'
    '.vt{vertical-align:top}'
    '.vb{vertical-align:bottom}'
    '.vm{vertical-align:middle}'
    // 着重号：WKWebView 只认 -webkit- 前缀。
    '.dot,.em-dot{-webkit-text-emphasis:circle;text-emphasis:circle;'
    '-webkit-text-emphasis-position:under right;'
    'text-emphasis-position:under right}';
