const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict'),path=require('path');
const root=path.resolve(__dirname,'..'),ax=fs.existsSync(path.join(root,'ui/recovery.js')),source=fs.readFileSync(path.join(root,ax?'ui/recovery.js':'payload/padavan/recovery.js'),'utf8');
function setup({enabled=true}={}){
 const els={},calls=[],answers=[],questions=[],timers=[],navigation=[];
 function element(){return{value:'',disabled:false,hidden:false,textContent:'',children:[],classList:{toggle(){}},setAttribute(){},append(...v){this.children.push(...v)},replaceChildren(){this.children=[]},focus(){},addEventListener(){},showModal(){},close(){},querySelector:s=>find(s.startsWith('#')?s.slice(1):s)}}
 const find=id=>els[id]||(els[id]=element());
 const plan={id:'06060606',source:'latest',verified:true,executor_ready:enabled,archive_checked:true,config_checked:true,token:'a'.repeat(16),expires_in:180,manifest_sha256:'b'.repeat(64),backup:{model:ax?'AX5':'K2P',created:1700000000,core_version:'1.12.13',size:1024,files:[{name:'application.tar.gz',size:1024,sha256:'c'.repeat(64)}]}};
 const c=vm.createContext({document:{activeElement:null,createElement:element,body:{append(){}}},JSON,Date,TextEncoder,Uint8Array,URLSearchParams,
  crypto:{getRandomValues:a=>a.fill(6)},setTimeout:fn=>{timers.push(fn);return timers.length},clearTimeout(){},
  nativeState:{remote_transport:'webdav',remote_enabled:true,remote_verified:true,active:false,core_version:'1.12.13'},mirrorDirty:false,manageBusy:false,advancedActive:false,
  backendBase:'/cgi-bin/luci/web/shellcrash',backupModel:()=>ax?'AX5':'K2P',decode:()=>'',
  location:{pathname:'/panel',search:'',assign:u=>navigation.push(u)},localStorage:{getItem(){return null},setItem(){}},
  confirm:text=>{questions.push(text);return answers.shift()??false},pauseMeasurements(){},pauseSites(){},showService(){},paintMirror(){},mirrorFeedback(){},
  upload:async()=>{},control:async(...args)=>calls.push(args),waitJob:async()=>{},nativeRead:async()=>plan,syncNative:async()=>{}});
 vm.runInContext(source,c);c.openRecoveryWindow();return{c,find,calls,answers,questions,timers,navigation,plan};
}
(async()=>{
 let s=setup();await s.find('recovery-check').onclick();assert.equal(s.find('recovery-execute').disabled,false);
 s.answers.push(false);await s.find('recovery-execute').onclick();assert.equal(s.questions.length,1);assert.equal(s.calls.filter(x=>x[0]==='sc-restorego.sh').length,0);
 s=setup();await s.find('recovery-check').onclick();s.answers.push(true,false);await s.find('recovery-execute').onclick();assert.equal(s.questions.length,2);assert.equal(s.navigation.length,0);
 s=setup();await s.find('recovery-check').onclick();s.answers.push(true,true);await s.find('recovery-execute').onclick();assert.equal(s.calls.at(-1)[0],'sc-restorego.sh');assert.deepEqual(Array.from(s.calls.at(-1)[1]),['06060606','a'.repeat(16)]);assert.equal(s.navigation.length,1);assert(s.navigation[0].includes('recovery-status'));await s.find('recovery-execute').onclick();assert.equal(s.calls.filter(x=>x[0]==='sc-restorego.sh').length,1);
 s=setup();await s.find('recovery-check').onclick();s.timers.at(-1)();s.answers.push(true,true);await s.find('recovery-execute').onclick();assert.equal(s.find('recovery-execute').disabled,true);assert.equal(s.questions.length,0);
 s=setup();await s.find('recovery-check').onclick();s.find('recovery-source').value='baseline';s.find('recovery-source').onchange();assert.equal(s.find('recovery-execute').disabled,true);
 s=setup({enabled:false});await s.find('recovery-check').onclick();assert.equal(s.find('recovery-execute').disabled,true);
 s=setup();await s.find('recovery-check').onclick();s.c.mirrorDirty=true;s.answers.push(true,true);await s.find('recovery-execute').onclick();assert.equal(s.questions.length,0);
 console.log('recovery UI: native gate, both cancellations, single submission, source/draft/expiry invalidation and independent result navigation passed');
})().catch(e=>{console.error(e);process.exitCode=1});
