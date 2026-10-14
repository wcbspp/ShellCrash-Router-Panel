const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const root=path.resolve(__dirname,'..'),ax=fs.existsSync(path.join(root,'ui/manager.js'));
const text=fs.readFileSync(path.join(root,ax?'ui/manager.js':'payload/padavan/manager.js'),'utf8');
const source=text.slice(text.indexOf('let trafficPrevious=null'));
const fields=Object.fromEntries(['traffic-up','traffic-down','traffic-up-total','traffic-down-total','traffic-sample-state','traffic-scope'].map(id=>[id,{}]));
let response={running:true,epoch:'1-10',upTotal:1024,downTotal:2048,checked_ms:1000},reads=0;
const c=vm.createContext({el:id=>fields[id],running:true,manageBusy:false,nativeState:{},advancedActive:false,document:{hidden:false,addEventListener(){}},window:{addEventListener(){}},setInterval(){},setTimeout,clearTimeout,AbortController,api:async()=>{reads++;return response},nativeRead:async()=>{reads++;return response}});vm.runInContext(source,c);
(async()=>{
 c.paintTrafficScope({running:true,traffic_mode:'rule',cn_bypass:{active:true}});assert.equal(fields['traffic-scope'].textContent,'国内绕过中');assert(fields['traffic-scope'].title.includes('不是订阅'));c.paintTrafficScope({running:true,traffic_mode:'direct'});assert.equal(fields['traffic-scope'].textContent,'接管已暂停');c.paintTrafficScope({running:true,traffic_mode:'global'});assert.equal(fields['traffic-scope'].textContent,'全局代理中');
 await c.pollTraffic();assert.equal(fields['traffic-up-total'].textContent,'1.0 KB');assert.equal(fields['traffic-up'].textContent,'采样中');
 response={...response,upTotal:5120,downTotal:10240,checked_ms:5000};await c.pollTraffic();assert.equal(fields['traffic-up'].textContent,'1.0 KB/s');assert.equal(fields['traffic-down'].textContent,'2.0 KB/s');
 response={...response,epoch:'2-20',upTotal:0,downTotal:0,checked_ms:9000};await c.pollTraffic();assert.equal(fields['traffic-up'].textContent,'采样中');assert.equal(fields['traffic-down-total'].textContent,'0 B');
 response={...response,up:12,down:34,checked_ms:13000};await c.pollTraffic();assert.equal(fields['traffic-up'].textContent,'12 B/s');
 const before=reads;c.advancedActive=true;await c.pollTraffic();assert.equal(reads,before);assert.equal(fields['traffic-up'].textContent,'12 B/s');assert.equal(fields['traffic-sample-state'].textContent,'采样暂停');c.advancedActive=false;
 response={error:'traffic_unavailable'};await c.pollTraffic();assert.equal(fields['traffic-sample-state'].textContent,'更新失败');assert.equal(fields['traffic-up'].textContent,'12 B/s');
 c.running=false;await c.pollTraffic();assert.equal(fields['traffic-up-total'].textContent,'未运行');assert.equal(fields['traffic-sample-state'].textContent,'内核已停止');
 assert.equal(c.trafficBytes(-1),'待统计');assert.equal(c.trafficBytes(NaN),'待统计');console.log('kernel counters: delta speed, core reset, native speed, failure, stopped and paused sampling passed');
})().catch(e=>{console.error(e);process.exitCode=1});
