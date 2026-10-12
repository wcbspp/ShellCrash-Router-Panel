const fs=require('fs'),vm=require('vm'),assert=require('assert');
(async()=>{for(const [root,file]of [[require('path').resolve(__dirname,'..'),'ui/manager.js']]){
 const s=fs.readFileSync(root+'/'+file,'utf8'),fn=s.slice(s.indexOf('async function saveNativeQuickPolicies(){'),s.indexOf("el('quick-save').onclick=async()=>{"));
 let calls=[],failAt=0,gets=0;
 const p={G:{type:'Selector',all:['a','b'],now:'a'},C:{type:'Selector',all:['a','b'],now:'a'},A:{type:'Selector',all:['a','b'],now:'a'},H:{type:'Selector',all:['a','b'],now:'a'}};
 const box={console,note(){},showService(){},pauseMeasurements(){},pauseSites(){},paintQuickActions(){},paintQuickPolicies(){},render(){},refresh:async()=>{},api:async(path,method,body)=>{if(!method){gets++;return{proxies:p}}calls.push([path,body.name]);if(failAt&&calls.length===failAt)throw Error('failure');p[decodeURIComponent(path.slice(9))].now=body.name;return null},proxies:p,running:true};
 vm.createContext(box);vm.runInContext("let manageBusy=false;const quickDrafts=new Map([['Google','b'],['GPT','b'],['AI','b'],['GitHub','b']]);const quickPolicies=[{name:'Google',tag:'G',domains:['g.com']},{name:'GPT',tag:'C',domains:['c.com']},{name:'AI',tag:'A',domains:['a.com']},{name:'GitHub',tag:'H',domains:['h.com']}];const policyRows=quickPolicies.map(p=>({kind:'suffix',domain:p.domains[0],target:p.tag}));"+fn,box);
 assert.equal(await vm.runInContext('saveNativeQuickPolicies()',box),true);assert.equal(calls.length,4);assert.equal(gets,1);assert.equal(vm.runInContext('quickDrafts.size',box),0);assert(Object.values(p).every(x=>x.now==='b'));
 for(const x of Object.values(p))x.now='a';calls=[];failAt=3;vm.runInContext("for(const p of quickPolicies)quickDrafts.set(p.name,'b')",box);
 await vm.runInContext('saveNativeQuickPolicies()',box);assert(Object.values(p).every(x=>x.now==='a'));assert.equal(vm.runInContext('quickDrafts.size',box),4);assert.equal(calls.length,5);
 calls=[];vm.runInContext("quickDrafts.set('GPT','')",box);assert.equal(await vm.runInContext('saveNativeQuickPolicies()',box),false);assert.equal(calls.length,0);
 console.log(root+': native batch, verification, reverse rollback, draft retention and structural fallback passed');
}})().catch(e=>{console.error(e);process.exit(1)});
