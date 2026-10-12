// Only the embedded dashboard can ask its authenticated parent to reach the core.
(()=>{const original=window.fetch.bind(window),pending=new Map();let serial=0;
window.fetch=(input,init={})=>{const url=new URL(typeof input==='string'?input:input.url,location.href);if(url.hostname!=='shellcrash.invalid')return original(input,init);const id=++serial;return new Promise((resolve,reject)=>{const timer=setTimeout(()=>{pending.delete(id);reject(Error('管理请求超时'))},15000);pending.set(id,{resolve,reject,timer});parent.postMessage({type:'sc-dashboard-request',id,path:url.pathname+url.search,method:init.method||'GET',body:init.body||''},location.origin)})};
window.addEventListener('message',e=>{if(e.source!==parent||e.origin!==location.origin||e.data?.type!=='sc-dashboard-response')return;const p=pending.get(e.data.id);if(!p)return;clearTimeout(p.timer);pending.delete(e.data.id);p.resolve(new Response(JSON.stringify(e.data.data||{error:e.data.error}),{status:e.data.status||200,headers:{'Content-Type':'application/json'}}))});
// Streaming endpoints are not exposed by the authenticated HTTP bridge.
window.WebSocket=class {constructor(){this.readyState=3;setTimeout(()=>{this.onerror?.({});this.onclose?.({})},0)}addEventListener(name,fn){if(name==='error'||name==='close')setTimeout(fn,0)}close(){}send(){}};
})();

// The embedded dashboard queries rules; edits stay in the lightweight UI.
window.addEventListener('DOMContentLoaded',()=>{
 const protect=()=>{for(const link of document.querySelectorAll('a[href]'))if(['#/configs','#/config','#/logs','#/home','#/'].includes(link.getAttribute('href')))link.hidden=true;if(!location.hash.startsWith('#/rules'))return;for(const item of document.querySelectorAll('[role="switch"]'))if(!item.disabled){item.disabled=true;item.setAttribute('aria-disabled','true');item.title='规则修改请返回轻量面板'}};
 new MutationObserver(protect).observe(document.body,{childList:true,subtree:true});window.addEventListener('hashchange',protect);protect();
});
