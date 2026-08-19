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
  var rect=image.getBoundingClientRect();
  post({type:'image',src:src,alt:image.getAttribute('alt')||'',
    rect:{x:rect.left,y:rect.top,w:rect.width,h:rect.height}});
  return true;
}
var suppressImageClick=false;
function initImages(){
  var timer=null,startX=0,startY=0,tracking=false;
  function cancel(){
    if(timer){clearTimeout(timer);timer=null;}
    tracking=false;
  }
  window.__nvSetLongPressPreview=function(value){
    longPressPreview=!!value;
    if(!longPressPreview)cancel();
  };
  document.addEventListener('touchstart',function(event){
    cancel();
    suppressImageClick=false;
    if(!longPressPreview||event.touches.length!==1)return;
    var image=findImage(event.target);
    if(!image)return;
    startX=event.touches[0].clientX;
    startY=event.touches[0].clientY;
    tracking=true;
    timer=setTimeout(function(){
      timer=null;
      tracking=false;
      suppressImageClick=sendImage(image,null);
    },500);
  },{passive:true});
  document.addEventListener('touchmove',function(event){
    if(!tracking||event.touches.length!==1){cancel();return;}
    var dx=event.touches[0].clientX-startX;
    var dy=event.touches[0].clientY-startY;
    // 手指静止时也会有少量坐标抖动；只在确实开始拖动后取消长按。
    if(dx*dx+dy*dy>144)cancel();
  },{passive:true});
  document.addEventListener('touchend',cancel,{passive:true});
  document.addEventListener('touchcancel',cancel,{passive:true});
  document.addEventListener('contextmenu',function(event){
    if(findImage(event.target))event.preventDefault();
  });
  // 长按图片会被 WebView 当成原生拖拽，拖出一张半透明小图，直接掐掉。
  document.addEventListener('dragstart',function(event){event.preventDefault();});
}

var stablePage=0;
function scrollToLeft(left){
  var el=scroller();
  el.scrollLeft=Math.max(0,Math.min(maxScrollX(),left));
}
// 只有翻页模式会翻：滚动模式靠手指滑，点击不参与移动。
function turn(direction){
  var width=pageWidth();
  var maxPage=Math.max(0,Math.round(maxScrollX()/width));
  var target=stablePage+direction;
  if(target<0||target>maxPage)return false;
  stablePage=target;
  scrollToLeft(target*width);
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
      if(image&&suppressImageClick){
        suppressImageClick=false;
        event.preventDefault();
        event.stopPropagation();
        return;
      }
      if(image&&!longPressPreview){
        if(sendImage(image,event))return;
      }
    }
    // 滚动模式没有点击翻页，整屏都只切工具栏。
    if(!paged){
      post({type:'tap',zone:'center',boundary:false});
      return;
    }
    var width=window.innerWidth||1;
    if(event.clientX<=width*0.3){
      event.preventDefault();
      window.__nvTurn(-1);
    }else if(event.clientX>=width*0.7){
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
