const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const root=path.resolve(__dirname,'..'),ax=fs.existsSync(path.join(root,'ui/manager.js'));
const text=fs.readFileSync(path.join(root,ax?'ui/manager.js':'payload/padavan/manager.js'),'utf8');
const source=text.match(/const transportEditable=[\s\S]*?el\('transport-mode'\)\.onchange=[^\n]+/)[0];
function fixture(){
 const cl={toggle(){}};const e={'transport-mode':{value:'redir',options:[{value:'redir'},{value:'mixed'}],classList:cl},'transport-save':{disabled:true,classList:cl},'transport-state':{},'transport-result':{},'policy-scope':{},'dns-udp-scope':{}};
 const state={running:true,transport:{configured:'redir',active:'redir',mixed_available:true}};let failed=false;const calls=[];
 const c=vm.createContext({el:id=>e[id],nativeState:state,document:{activeElement:null},manageBusy:false,advancedActive:false,running:true,crypto:{getRandomValues:a=>a.fill(1)},Uint8Array,pauseMeasurements(){},pauseSites(){},showService(){},note:(...x)=>calls.push(['notice',...x]),control:async(script,args)=>{calls.push([script,args]);if(failed)throw Error('fixture failed');state.transport={configured:args[1],active:args[1],mixed_available:true}},waitJob:async()=>({message_b64:''}),invalidateSiteResults(){calls.push(['clear-sites'])},syncNative:async()=>{},refresh:async()=>{},decode:v=>v,render(){},autoMeasure(){}});
 vm.runInContext(source,c);return {c,e,state,calls,fail:()=>failed=true};
}
(async()=>{
 let x=fixture();x.c.paintTransport(x.state);assert(x.e['transport-save'].disabled);x.e['transport-mode'].value='mixed';x.e['transport-mode'].onchange();assert.equal(x.e['transport-save'].disabled,false);
 x.c.paintTransport(x.state);assert.equal(x.e['transport-mode'].value,'mixed','polling must preserve draft');await x.c.saveTransport();assert.equal(x.calls.some(([s])=>s==='sc-transport.sh'),true);
 {
  const cancel=fixture();cancel.c.paintTransport(cancel.state);cancel.e['transport-mode'].value='mixed';cancel.e['transport-mode'].onchange();cancel.e['transport-mode'].value='redir';cancel.e['transport-mode'].onchange();assert(!vm.runInContext('transportDirty',cancel.c));assert(cancel.e['transport-save'].disabled);
  assert.equal(x.state.transport.active,'mixed');assert(x.calls.some(([s])=>s==='clear-sites'));
  x=fixture();x.fail();x.e['transport-mode'].value='mixed';x.e['transport-mode'].onchange();await x.c.saveTransport();assert.equal(x.state.transport.active,'redir');assert.equal(x.e['transport-mode'].value,'mixed');assert(!x.e['transport-save'].disabled,'failed draft remains retryable');
  x=fixture();x.state.transport.mixed_available=false;x.c.paintTransport(x.state);assert(x.e['transport-mode'].options[1].disabled);x.e['transport-mode'].value='mixed';x.e['transport-mode'].onchange();assert(x.e['transport-save'].disabled);
  x=fixture();x.e['transport-mode'].value='mixed';x.e['transport-mode'].onchange();x.c.advancedActive=true;await x.c.saveTransport();assert(!x.calls.some(([s])=>s==='sc-transport.sh'));
 }
 console.log('transport UI: draft preservation, capability gates, restart action, failure retry and advanced exclusion passed');
})().catch(e=>{console.error(e);process.exitCode=1});
