import 'reader_engine.dart';

const String readerBridgeChannel = 'ReaderBridge';

/// 章节正文文档构建。正文只能跑在 WebView 里（字体是 WOFF2，见 `ReaderFontCache`），
/// 分页交给 CSS 多列。主题/排版全走 CSS 变量，改设置只注入一小段 JS，免得重载丢位置。

final RegExp _openingTagPattern = RegExp(r'^<([a-zA-Z][\w:-]*)');
final RegExp _relativeImagePattern = RegExp(
  r'''(<img\b[^>]*\bsrc\s*=\s*)("|')(?![a-zA-Z][a-zA-Z0-9+.-]*:|#|//)([^"']*)\2''',
  caseSensitive: false,
);

String _escapeAttribute(String value) =>
    value.replaceAll('&', '&amp;').replaceAll('"', '&quot;');

/// 相对图片地址补全到 API 源站，`data:` 文档解析不了相对路径。
String rebaseReaderImages(String html, String imageBaseUrl) =>
    html.replaceAllMapped(_relativeImagePattern, (match) {
      final source = match[3]!;
      final separator = source.startsWith('/') ? '' : '/';
      return '${match[1]}${match[2]}$imageBaseUrl$separator$source${match[2]}';
    });

/// 给每个块的开标签打上 `data-nv-locator`，JS 才能把可视位置换算成服务端进度。
String _bodyMarkup(
  List<NovelReaderBlock> blocks,
  String fallbackHtml,
  String imageBaseUrl,
) {
  if (blocks.isEmpty) return rebaseReaderImages(fallbackHtml, imageBaseUrl);
  final buffer = StringBuffer();
  for (final block in blocks) {
    final locator = _escapeAttribute(block.locator);
    final html = rebaseReaderImages(block.html, imageBaseUrl);
    final opening = _openingTagPattern.firstMatch(html);
    if (opening == null) {
      buffer.write('<div data-nv-locator="$locator">$html</div>');
      continue;
    }
    buffer
      ..write(html.substring(0, opening.end))
      ..write(' data-nv-locator="$locator"')
      ..write(html.substring(opening.end));
  }
  return buffer.toString();
}

class ReaderTypography {
  const ReaderTypography({
    required this.backgroundColor,
    required this.textColor,
    required this.fontSize,
    required this.lineHeight,
    required this.sidePadding,
    required this.topPadding,
    required this.bottomPadding,
    required this.firstLineIndent,
  });

  /// `#RRGGBB` 页面底色。
  final String backgroundColor;

  /// `#RRGGBB` 正文色。
  final String textColor;
  final double fontSize;
  final double lineHeight;
  final double sidePadding;
  final double topPadding;
  final double bottomPadding;
  final bool firstLineIndent;

  String get _variables =>
      ':root{'
      '--nv-bg:$backgroundColor;'
      '--nv-fg:$textColor;'
      '--nv-font:${fontSize.toStringAsFixed(1)}px;'
      '--nv-line:${lineHeight.toStringAsFixed(2)};'
      '--nv-top:${topPadding.toStringAsFixed(1)}px;'
      '--nv-bottom:${bottomPadding.toStringAsFixed(1)}px;'
      '--nv-hpad:${sidePadding.toStringAsFixed(1)}px;'
      '--nv-indent:${firstLineIndent ? '2em' : '0'};'
      '}';
}

/// 排版变更时注入的脚本：只改 CSS 变量，阅读位置不丢。
String readerTypographyScript(ReaderTypography typography) {
  final style = <String, String>{
    '--nv-bg': typography.backgroundColor,
    '--nv-fg': typography.textColor,
    '--nv-font': '${typography.fontSize.toStringAsFixed(1)}px',
    '--nv-line': typography.lineHeight.toStringAsFixed(2),
    '--nv-top': '${typography.topPadding.toStringAsFixed(1)}px',
    '--nv-bottom': '${typography.bottomPadding.toStringAsFixed(1)}px',
    '--nv-hpad': '${typography.sidePadding.toStringAsFixed(1)}px',
    '--nv-indent': typography.firstLineIndent ? '2em' : '0',
  };
  final assignments = style.entries
      .map(
        (entry) =>
            "document.documentElement.style.setProperty('${entry.key}','${entry.value}');",
      )
      .join();
  return '(function(){$assignments'
      'if(window.__nvReflow)window.__nvReflow();})();';
}

/// 恢复阅读位置：优先按 locator 精确定位，找不到时退回百分比。
String readerRestoreScript(String? locator, double progression) {
  final target = locator == null ? 'null' : "'${_escapeJs(locator)}'";
  final ratio = progression.clamp(0.0, 1.0).toStringAsFixed(4);
  return '(function(){if(window.__nvRestore)'
      'window.__nvRestore($target,$ratio);})();';
}

/// 翻页/翻屏，`direction` 为 1 向后、-1 向前。
String readerTurnScript(int direction) =>
    '(function(){if(window.__nvTurn)window.__nvTurn($direction);})();';

String _escapeJs(String value) =>
    value.replaceAll('\\', '\\\\').replaceAll("'", "\\'").replaceAll('\n', ' ');

String buildReaderChapterDocument({
  required List<NovelReaderBlock> blocks,
  required String fallbackHtml,
  required String imageBaseUrl,
  required ReaderTypography typography,
  required bool paged,
  String? fontDataUrl,
  bool imagePreviewOnLongPress = false,
}) {
  final fontFace = fontDataUrl == null
      ? ''
      : "@font-face{font-family:'ChapterFont';font-display:block;"
            'src:url($fontDataUrl);font-style:normal;font-weight:400}';
  final fontFamily = fontDataUrl == null
      ? "'PingFang SC','Noto Sans SC',sans-serif"
      : "'ChapterFont','PingFang SC','Noto Sans SC',sans-serif";

  final layoutCss = paged
      // 多列容器放在 html 上：上下内边距会作用到每一列，放在 body 上只有首尾列生效。
      ? 'html{position:relative;width:100%;max-width:100%;height:100vh;'
            'max-height:100vh;margin:0!important;'
            'padding:var(--nv-top) 0 var(--nv-bottom)!important;box-sizing:border-box;'
            'column-width:100vw;column-gap:0;column-fill:auto;overflow-y:hidden}'
            'body{width:100%;max-width:100%;margin:0 auto!important;box-sizing:border-box;'
            'padding:0 var(--nv-hpad)}'
            'html,body{touch-action:none}'
      : 'body{padding:var(--nv-top) var(--nv-hpad) var(--nv-bottom)}';

  final css = <String>[
    typography._variables,
    'html,body{margin:0;padding:0;background:var(--nv-bg);color:var(--nv-fg)}',
    'html,body{scrollbar-width:none}'
        'html::-webkit-scrollbar,body::-webkit-scrollbar{display:none;width:0;height:0}',
    'body{font-family:$fontFamily;font-size:var(--nv-font);line-height:var(--nv-line);'
        'word-break:break-word;overflow-wrap:break-word;-webkit-text-size-adjust:100%}',
    'p{margin:0 0 .8em;text-indent:var(--nv-indent)}',
    'body>:last-child{margin-bottom:0!important}',
    'img{max-width:100%;height:auto}',
    'table{width:100%;max-width:100%;table-layout:fixed;border-collapse:collapse;margin:0 0 .8em}',
    'th,td{padding:0;vertical-align:top}',
    'td>img,th>img{display:block;width:100%;max-width:100%;height:auto}',
    'ruby rt{font-size:.5em;color:var(--nv-fg)}',
    'a{color:inherit;text-decoration:none}',
    '*{line-break:anywhere;-webkit-user-select:none!important;user-select:none!important;'
        '-webkit-touch-callout:none}',
    layoutCss,
  ].join();

  final script = _readerScript(
    paged: paged,
    imagePreviewOnLongPress: imagePreviewOnLongPress,
  );

  return '<!DOCTYPE html><html><head><meta charset="utf-8" />'
      '<meta name="viewport" content="width=device-width, initial-scale=1.0, '
      'maximum-scale=1.0, user-scalable=no" />'
      '<style>$fontFace$css</style>$script</head>'
      '<body>${_bodyMarkup(blocks, fallbackHtml, imageBaseUrl)}</body></html>';
}

String _readerScript({
  required bool paged,
  required bool imagePreviewOnLongPress,
}) {
  final flags =
      'var paged=$paged;var longPressPreview=$imagePreviewOnLongPress;';
  return '<script>(function(){$flags$_readerScriptBody})();</script>';
}

/// 桥接脚本：点击分区、进度上报、脚注与图片事件全部经由 `$readerBridgeChannel`。
const String _readerScriptBody = r'''
function post(payload){
  try{
    if(window.ReaderBridge&&window.ReaderBridge.postMessage){
      window.ReaderBridge.postMessage(JSON.stringify(payload));
    }
  }catch(e){}
}
function scroller(){return document.scrollingElement||document.documentElement;}
function inset(name){
  var raw=getComputedStyle(document.documentElement).getPropertyValue(name);
  var value=parseFloat(raw);
  return isNaN(value)?0:value;
}
function pageWidth(){
  var width=document.documentElement.getBoundingClientRect().width;
  return Math.max(1,width||scroller().clientWidth||window.innerWidth||1);
}
function maxScrollX(){var el=scroller();return Math.max(0,(el.scrollWidth||0)-(el.clientWidth||0));}
function maxScrollY(){var el=scroller();return Math.max(0,(el.scrollHeight||0)-(window.innerHeight||0));}
function progression(){
  if(paged){var mx=maxScrollX();return mx<=0?0:Math.min(1,Math.max(0,scroller().scrollLeft/mx));}
  var my=maxScrollY();
  return my<=0?0:Math.min(1,Math.max(0,(window.pageYOffset||scroller().scrollTop||0)/my));
}
function topLocator(){
  var probeY=Math.max(2,inset('--nv-top')+6);
  try{
    var el=document.elementFromPoint(Math.floor(window.innerWidth/2),probeY);
    while(el&&el!==document.body){
      if(el.getAttribute&&el.getAttribute('data-nv-locator')){
        return el.getAttribute('data-nv-locator');
      }
      el=el.parentElement;
    }
  }catch(e){}
  var nodes=document.querySelectorAll('[data-nv-locator]');
  for(var i=0;i<nodes.length;i++){
    var rect=nodes[i].getBoundingClientRect();
    if(paged?rect.right>1:rect.bottom>probeY){
      return nodes[i].getAttribute('data-nv-locator');
    }
  }
  return '';
}
var lastReport=0;
function report(force){
  var now=Date.now();
  if(!force&&now-lastReport<250)return;
  lastReport=now;
  var width=pageWidth();
  post({
    type:'position',
    progression:progression(),
    locator:topLocator(),
    page:paged?Math.round(scroller().scrollLeft/width)+1:0,
    pages:paged?Math.round(maxScrollX()/width)+1:0
  });
}
window.addEventListener('scroll',function(){report(false);},{passive:true});
window.addEventListener('resize',function(){report(true);});

function initFootnotes(){
  var links=document.querySelectorAll('a[data-reader-footnote-id], a.duokan-footnote');
  var index=0;
  for(var i=0;i<links.length;i++){
    var link=links[i];
    var id=link.getAttribute('data-reader-footnote-id')||(link.getAttribute('href')||'').replace('#','');
    if(!id)continue;
    index++;
    link.innerHTML='<sup style="font-size:.7em;line-height:0;vertical-align:super">['+index+']</sup>';
    (function(noteId){
      link.addEventListener('click',function(event){
        event.preventDefault();
        event.stopPropagation();
        post({type:'footnote',id:noteId});
      });
    })(id);
  }
}

function findImage(target){
  var current=target;
  while(current&&current!==document.body){
    if(current.tagName==='IMG'){
      return current.classList&&current.classList.contains('no-preview')?null:current;
    }
    current=current.parentElement;
  }
  return null;
}
function sendImage(image,event){
  if(!image)return false;
  var src=image.currentSrc||image.getAttribute('src');
  if(!src)return false;
  if(event){event.preventDefault();event.stopPropagation();}
  post({type:'image',src:src,alt:image.getAttribute('alt')||''});
  return true;
}
function initImages(){
  var timer=null;
  function cancel(){if(timer){clearTimeout(timer);timer=null;}}
  if(longPressPreview){
    document.addEventListener('touchstart',function(event){
      cancel();
      var image=findImage(event.target);
      if(!image)return;
      timer=setTimeout(function(){timer=null;sendImage(image,null);},500);
    },{passive:true});
    document.addEventListener('touchmove',cancel,{passive:true});
    document.addEventListener('touchend',cancel,{passive:true});
  }
  document.addEventListener('contextmenu',function(event){
    if(findImage(event.target))event.preventDefault();
  });
}

var stablePage=0;
function scrollToLeft(left){
  var el=scroller();
  el.scrollLeft=Math.max(0,Math.min(maxScrollX(),left));
}
function turn(direction){
  if(paged){
    var width=pageWidth();
    var maxPage=Math.max(0,Math.round(maxScrollX()/width));
    var target=stablePage+direction;
    if(target<0||target>maxPage)return false;
    stablePage=target;
    scrollToLeft(target*width);
    report(true);
    return true;
  }
  var viewport=Math.max(1,window.innerHeight-inset('--nv-top')-inset('--nv-bottom'));
  var current=window.pageYOffset||scroller().scrollTop||0;
  var limit=maxScrollY();
  if(direction>0&&current>=limit-1)return false;
  if(direction<0&&current<=1)return false;
  window.scrollTo({top:Math.max(0,Math.min(limit,current+direction*viewport)),behavior:'auto'});
  report(true);
  return true;
}
window.__nvTurn=function(direction){
  if(!turn(direction))post({type:'tap',zone:direction>0?'next':'prev',boundary:true});
};
window.__nvReflow=function(){setTimeout(function(){report(true);},60);};
window.__nvRestore=function(locator,ratio){
  var node=null;
  if(locator){
    try{node=document.querySelector('[data-nv-locator="'+locator.replace(/"/g,'\\"')+'"]');}catch(e){node=null;}
  }
  if(paged){
    var width=pageWidth();
    var left;
    if(node){
      left=node.getBoundingClientRect().left+scroller().scrollLeft;
    }else{
      left=Math.max(0,Math.min(1,ratio||0))*maxScrollX();
    }
    left=Math.round(left/width)*width;
    stablePage=Math.round(left/width);
    scrollToLeft(left);
  }else if(node){
    var top=node.getBoundingClientRect().top+(window.pageYOffset||0)-inset('--nv-top');
    window.scrollTo({top:Math.max(0,top),behavior:'auto'});
  }else{
    window.scrollTo({top:Math.max(0,Math.min(1,ratio||0))*maxScrollY(),behavior:'auto'});
  }
  setTimeout(function(){report(true);},60);
};

function initPaged(){
  var el=scroller();
  stablePage=Math.round((el.scrollLeft||0)/pageWidth())||0;
  el.addEventListener('scroll',function(){
    stablePage=Math.round((el.scrollLeft||0)/pageWidth());
  },{passive:true});

  var dragging=false,startX=0,startLeft=0,lastX=0,lastT=0,velocity=0,moved=false;
  document.addEventListener('touchstart',function(event){
    if(event.touches.length!==1)return;
    dragging=true;moved=false;
    startX=event.touches[0].clientX;
    startLeft=el.scrollLeft;
    lastX=startX;lastT=Date.now();velocity=0;
  },{passive:false});
  document.addEventListener('touchmove',function(event){
    if(!dragging||event.touches.length!==1)return;
    event.preventDefault();
    var x=event.touches[0].clientX;
    var dx=x-startX;
    if(Math.abs(dx)>8)moved=true;
    var now=Date.now();
    var dt=now-lastT;
    if(dt>0)velocity=velocity*0.7+((x-lastX)/dt)*0.3;
    lastX=x;lastT=now;
    el.scrollLeft=startLeft-dx;
  },{passive:false});
  document.addEventListener('touchend',function(event){
    if(!dragging)return;
    dragging=false;
    if(!moved)return;
    var width=pageWidth();
    var startPage=Math.round(startLeft/width);
    var distance=event.changedTouches[0].clientX-startX;
    var targetPage;
    // 甩动或大幅拖动：以拖动起点为基准整页翻动，避免叠加已跟手的位移。
    if(Math.abs(distance)>width*0.18||Math.abs(velocity)>0.4){
      targetPage=startPage-Math.sign(distance||velocity);
    }else{
      targetPage=Math.round(el.scrollLeft/width);
    }
    var maxPage=Math.max(0,Math.round(maxScrollX()/width));
    stablePage=Math.max(0,Math.min(maxPage,targetPage));
    scrollToLeft(stablePage*width);
    report(true);
  },{passive:true});
}

function initTapZones(){
  document.addEventListener('click',function(event){
    if(event.target&&event.target.closest){
      if(event.target.closest('a')||event.target.closest('button'))return;
      var image=findImage(event.target);
      if(image&&!longPressPreview){
        if(sendImage(image,event))return;
      }
    }
    var width=window.innerWidth||1;
    var x=event.clientX;
    if(x<width/3){
      event.preventDefault();
      window.__nvTurn(-1);
    }else if(x>width*2/3){
      event.preventDefault();
      window.__nvTurn(1);
    }else{
      post({type:'tap',zone:'center',boundary:false});
    }
  });
}

function init(){
  initFootnotes();
  initImages();
  if(paged)initPaged();
  initTapZones();
  post({type:'ready'});
  setTimeout(function(){report(true);},120);
  if(document.fonts&&document.fonts.ready){
    document.fonts.ready.then(function(){setTimeout(function(){report(true);},200);});
  }
}
if(document.readyState==='loading'){
  document.addEventListener('DOMContentLoaded',init);
}else{
  init();
}
''';
