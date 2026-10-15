const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict'),path=require('path');
const root=path.resolve(__dirname,'..'),ax=fs.existsSync(path.join(root,'ui/manager.js'));
const source=fs.readFileSync(path.join(root,ax?'ui/manager.js':'payload/padavan/manager.js'),'utf8');
const section=source.slice(source.indexOf('let mirrorDirty='),source.indexOf('async function downloadBackup('));
const b64=s=>Buffer.from(s).toString('base64');
function setup(){
 const elements={},calls=[],questions=[],answers=[];
 const el=id=>elements[id]||(elements[id]={value:'',checked:false,disabled:false,hidden:false,textContent:'',classList:{toggle(){}}});
 const state={remote_transport:'webdav',remote_enabled:true,remote_verified:true,mirror_base_b64:b64('https://backup.example/dav'),webdav_user_b64:b64('test'),pressure:'normal'};
 const c=vm.createContext({JSON,Date,TextEncoder,Uint8Array,nativeState:state,el,manageBusy:false,advancedActive:false,running:true,
  crypto:{getRandomValues:a=>a.fill(6)},decode:s=>Buffer.from(s,'base64').toString(),confirm:text=>{questions.push(text);return answers.shift()??false},
  pauseMeasurements(){},pauseSites(){},showService(){c.paintMirror()},render(){},syncNative:async()=>{},waitJob:async()=>{},
  control:async(...args)=>calls.push(args),nativeRead:async kind=>kind==='remotecatalog'?{state:'ready',baseline_b64:state.remote_baseline_b64}:{state:'connected'}});
 vm.runInContext(section,c);c.paintMirror();return {c,el,calls,questions,answers,state};
}
(async()=>{
 let s=setup();assert.equal(s.el('baseline-create').textContent,'创建基础版本');
 assert.equal(s.el('backup-path-imports').textContent,'https://backup.example/dav/shellcrash-panel/'+(ax?'AX5':'K2P')+'/imports/');
 await s.c.createBaseline();assert.equal(s.calls.length,0);assert.equal(s.questions.length,1);
 s=setup();s.answers.push(true,false);await s.c.createBaseline();assert.equal(s.calls.length,0);assert.equal(s.questions.length,2);
 s=setup();s.answers.push(true,true);await s.c.createBaseline();assert.equal(s.calls.length,1);assert.equal(s.calls[0][0],'sc-baselinecreate.sh');assert.equal(s.calls[0][1][1],'create');assert(s.el('mirror-message').className.includes('success'));
 s=setup();s.state.remote_baseline_b64=b64(JSON.stringify({format:2,sha256:'a'.repeat(64),created:1234,size:4567}));s.c.paintMirror();assert.equal(s.el('baseline-create').textContent,'替换基础版本');assert(s.el('baseline-version').textContent.includes('独立保留'));
 s.answers.push(true,true);await s.c.createBaseline();assert.equal(s.calls[0][1][1],'replace');assert(s.questions[0].includes('替换'));
 s=setup();s.state.remote_enabled=false;s.c.paintMirror();s.answers.push(true,true);await s.c.createBaseline();assert.equal(s.calls.length,0);assert(s.el('baseline-create').disabled);
 s=setup();s.c.waitJob=async()=>{throw Error('校验失败')};s.answers.push(true,true);await s.c.createBaseline();assert(s.el('mirror-message').className.includes('error'));assert(s.el('mirror-message').textContent.includes('原基础版本保留'));assert(!s.c.manageBusy);
 const html=fs.readFileSync(path.join(root,ax?'ui/index.html':'payload/ui/index.html'),'utf8');
 assert(html.includes('<details id="baseline-section"'));assert(!html.includes('<details id="baseline-section" open'));
 assert(html.includes('id="backup-path-imports"'));assert(!section.includes('setInterval'));
 console.log('baseline UI: isolated collapsed entry, model-specific import path, two confirmations, disabled gate and failure feedback passed');
})().catch(e=>{console.error(e);process.exitCode=1});
