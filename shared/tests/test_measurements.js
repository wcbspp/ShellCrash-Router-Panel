const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const html=fs.readFileSync(fs.existsSync('ui/index.html')?'ui/index.html':'payload/ui/index.html','utf8');
const source=html.match(/let measureGeneration=0[\s\S]*?(?=async function refresh\()/)[0];
function fixture(api){
 const store=new Map(),delays=new Map(),calls=[];
 const ctx=vm.createContext({delays,api:async(...args)=>{calls.push(args);return api(...args)},running:true,manageBusy:false,activeTab:'nodes',document:{hidden:false},nativeState:{pressure:'normal'},siteBusy:false,AbortController,Date,Number,Set,Map,sessionStorage:{getItem:k=>store.get(k),setItem:(k,v)=>store.set(k,v),removeItem:k=>store.delete(k)},setTimeout:(fn,ms)=>setTimeout(fn,ms===200?0:ms),clearTimeout,el:()=>({children:[]}),note(){}});
 vm.runInContext(source,ctx);return {ctx,delays,calls,store};
}
async function drain(ctx){await vm.runInContext('pumpMeasurements()',ctx);for(let i=0;i<100&&vm.runInContext('measureWorker',ctx);i++)await new Promise(r=>setTimeout(r,5));assert.equal(vm.runInContext('measureWorker',ctx),false)}
(async()=>{
 const f=fixture(async path=>({delay:path.includes('bad')?0:123}));
 f.ctx.queueMeasurements(['node /中文','bad','node /中文']);await drain(f.ctx);
 assert.equal(f.calls.length,2);assert(f.calls.every(c=>c[1]==='GET'&&c[0].includes('/delay?timeout=3000&url=')));
 assert(f.calls[0][0].startsWith('/proxies/'+encodeURIComponent('node /中文')+'/delay?'));
 assert.equal(f.delays.get('node /中文').delay,123);assert.equal(f.delays.get('bad').failed,true);assert.equal(f.store.size,0);
 f.ctx.measure('node /中文');await drain(f.ctx);assert.equal(f.calls.length,3);
 const failed=fixture(async()=>{throw Object.assign(Error('timeout'),{status:504})});failed.ctx.queueMeasurements(['node']);await drain(failed.ctx);assert.equal(failed.calls.length,1);assert.equal(failed.delays.get('node').reason,'超时');
 let resolve;const cancelled=fixture(()=>new Promise(r=>{resolve=r}));cancelled.ctx.queueMeasurements(['first','second']);cancelled.ctx.pauseMeasurements();resolve({delay:42});await drain(cancelled.ctx);assert.equal(cancelled.calls.length,1);assert.equal(cancelled.delays.get('first').delay,undefined);assert.equal(cancelled.delays.get('second').queued,false);
 const pressure=fixture(async()=>({delay:42}));pressure.ctx.nativeState.pressure='protect';pressure.ctx.queueMeasurements(['node']);await drain(pressure.ctx);assert.equal(pressure.calls.length,0);
 assert(!html.includes('每条测三次'));assert(html.includes('每个节点只测一次'));
 console.log('single GET per node, deduplication, manual retest, timeout without retry, cancellation and pressure guard passed');
})().catch(e=>{console.error(e);process.exitCode=1});
