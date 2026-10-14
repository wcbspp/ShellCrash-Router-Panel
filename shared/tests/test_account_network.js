const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict'),path=require('path');
const root=path.resolve(__dirname,'..'),source=fs.readFileSync(path.join(root,fs.existsSync(path.join(root,'ui/sites.js'))?'ui/sites.js':'payload/padavan/sites.js'),'utf8');
const parts=source.slice(source.indexOf('// On-demand browser IP'));
const elements={};for(const id of ['ip-check','ip-v4','ip-v6','ip-summary','quota-refresh','quota-summary','quota-progress','quota-detail'])elements[id]={textContent:'',classList:{toggle(){}},disabled:false};
let requests=[],timers=new Set(),fetchMode='ok',read='{"state":"unknown"}',resolveRead;
const context=vm.createContext({console,Date,Number,JSON,Promise,AbortController,manageBusy:false,nativeState:{},el:id=>elements[id],document:{addEventListener(){},hidden:false},window:{addEventListener(){}},setTimeout(fn,ms){const t=setTimeout(fn,ms);timers.add(t);return t},clearTimeout(t){clearTimeout(t);timers.delete(t)},nativeRead:async()=>resolveRead?await new Promise(r=>resolveRead=r):read,fetch:async(url,opts)=>{requests.push({url,opts});if(fetchMode==='fail')throw Error('network');return {ok:true,text:async()=>JSON.stringify({ip:url.includes('api6')?'2001:db8::1':'198.51.100.2'})}}});
vm.runInContext(parts,context);
(async()=>{
 assert(context.validExitIP('198.51.100.2',false));assert(!context.validExitIP('999.1.2.3',false));assert(!context.validExitIP('<script>',true));assert(context.validExitIP('2001:db8::1',true));
 await context.checkExitIP();assert.equal(requests.length,2);assert.equal(elements['ip-v4'].textContent,'198.51.100.2');assert.equal(elements['ip-v6'].textContent,'2001:db8::1');assert(!elements['ip-check'].disabled);assert.equal(timers.size,0);assert(requests.every(r=>r.opts.credentials==='omit'));
 context.resetExitIP();assert.equal(elements['ip-v4'].textContent,'尚未检测');assert(elements['ip-summary'].textContent.includes('出口可能'));fetchMode='fail';await context.checkExitIP();assert.equal(elements['ip-v6'].textContent,'未检测到 IPv6 出口');assert(!elements['ip-check'].disabled);
 const v=context.quotaView({state:'ok',upload:100,download:200,total:1000,expire:0});assert.equal(v.percent,30);assert(v.summary.includes('剩余 700 B'));assert(v.detail.includes('未提供到期时间'));
 assert.equal(context.quotaView({state:'ok',upload:100,download:1000,total:1000}).percent,100);assert(context.quotaView({state:'ok',upload:100,download:1000,total:1000}).bad);
 assert.equal(context.quotaView({state:'ok',expire:1800000000}).percent,null);assert.equal(context.quotaView({state:'ok',upload:1,download:2,total:0}).percent,null);
 for(const state of ['unavailable','request_failed','no_subscription','busy','memory'])assert.equal(context.quotaView({state}).percent,null);
 context.resetQuotaSource(42);read=JSON.stringify({state:'ok',upload:100,download:200,total:1000});await context.refreshQuota(false);assert.equal(elements['quota-progress'].value,30);assert(!elements['quota-refresh'].disabled);
 read='{"state":"memory"}';await context.refreshQuota(true);assert.equal(elements['quota-progress'].value,30);assert(elements['quota-detail'].textContent.includes('上次查询'));context.resetQuotaSource(43);assert(elements['quota-progress'].hidden,'new subscription must not reuse the old quota');
 assert(!parts.includes('setInterval'),'new feature must never create a polling loop');console.log('on-demand browser IP and quota: IP validation, network failure, partial/unlimited/overused quota, source invalidation and no polling passed');
})().catch(e=>{console.error(e);process.exitCode=1});
