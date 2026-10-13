const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const root=path.resolve(__dirname,'..'),file=fs.existsSync(path.join(root,'ui/manager.js'))?'ui/manager.js':'payload/padavan/manager.js';
const source=fs.readFileSync(path.join(root,file),'utf8').match(/let proxyMode='rule'[\s\S]*?el\('proxy-mode'\)\.onchange=setProxyMode;/)[0];
function setup(){
 const elements={'proxy-mode':{value:'rule',classList:{toggle(){}}},current:{textContent:''},'proxy-mode-help':{textContent:'',classList:{toggle(){}}},'traffic-state':{},'advanced-open':{},'dns-udp-scope':{},'policy-scope':{}},requests=[],messages=[];
 let mode='Rule',failure=false,invalidations=0;
 const proxies={main:{type:'Selector',all:['node'],now:'node'},node:{type:'AnyTLS'},GLOBAL:{all:['DIRECT','main'],now:'DIRECT'},DIRECT:{type:'Direct'}};
 const nativeState={active:false,traffic_mode:'rule'};
 const context={Set,Uint8Array,crypto:{getRandomValues:a=>a.fill(1)},el:k=>elements[k],document:{activeElement:null},running:true,manageBusy:false,nativeState,advancedActive:false,proxies,mainName:()=> 'main',groupLabel:()=> 'default',resolvedNode:n=>n==='GLOBAL'?proxies.GLOBAL.now:proxies.main.now,displayNodeLabel:(target,name,prefix)=>{target.textContent=prefix+String(name).replace(/🇹🇼\s*/g,'')},pauseMeasurements(){},pauseSites(){},autoMeasure(){},showService(){},syncNative:async()=>nativeState,waitJob:async()=>{},invalidateSiteResults:()=>invalidations++,activeTab:'configuration',note:(...a)=>messages.push(a),control:async(script,args)=>{requests.push([script,args]);if(failure)throw Error('fixture rejected');assert.equal(script,'sc-proxymode.sh');mode=args[1];nativeState.traffic_mode=mode},api:async(p,m,b)=>{
  requests.push([p,m,b]);if(p==='/configs'&&!m)return {mode};
  if(p==='/proxies')return {proxies};if(p==='/proxies/GLOBAL'){proxies.GLOBAL.now=b.name;return {ok:true}}throw Error(p);
 }};
 const c=vm.createContext(context);vm.runInContext(source,c);
 return {c,e:elements,requests,messages,setMode:v=>{mode=v},reject:()=>{failure=true},invalidations:()=>invalidations};
}
(async()=>{
 let s=setup();s.c.proxies.main.now='🇹🇼 台湾02';s.c.paintProxyMode();assert.equal(s.e.current.textContent,'default / 台湾02');s.c.proxies.main.now='node';await s.c.readProxyMode();assert.equal(s.e['proxy-mode'].value,'rule');
 s.e['proxy-mode'].value='direct';await s.c.setProxyMode();assert.equal(s.e['proxy-mode'].value,'direct');assert(s.e['dns-udp-scope'].textContent.includes('已暂停'));assert(s.e['policy-scope'].textContent.includes('恢复规则分流'));assert(s.invalidations()>0,'mode change clears stale website results');
 assert(s.requests.some(([p,args])=>p==='sc-proxymode.sh'&&args[1]==='direct'),'mode change must use router transaction');
 s.e['proxy-mode'].value='rule';await s.c.setProxyMode();assert.equal(s.e.current.textContent,'default / node');
 s.e['proxy-mode'].value='global';await s.c.setProxyMode();assert.equal(s.c.proxies.GLOBAL.now,'main');assert.equal(s.e['proxy-mode'].value,'global');
 s.setMode('Direct');await s.c.readProxyMode();assert(vm.runInContext('proxyModeConflict',s.c),'external core-only change is flagged');
 s=setup();s.reject();s.e['proxy-mode'].value='direct';await s.c.setProxyMode();assert.equal(s.e['proxy-mode'].value,'rule');assert(s.messages[0][1]);
 s=setup();s.c.proxies.main.now='DIRECT';s.e['proxy-mode'].value='global';await s.c.setProxyMode();assert(!s.requests.some(([p])=>p==='sc-proxymode.sh'),'DIRECT default must not be called global proxy');
 s=setup();s.c.advancedActive=true;s.e['proxy-mode'].value='direct';await s.c.setProxyMode();assert.equal(s.requests.length,0);
 console.log('router mode transaction, readback, DNS/result invalidation, DIRECT rejection, failure and advanced exclusion passed');
})().catch(e=>{console.error(e);process.exitCode=1});
