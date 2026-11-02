const fs=require('fs'),vm=require('vm'),assert=require('assert');
const source=fs.readFileSync('shared/ui/health.js.in','utf8').split("let oomEvidence='';")[1].split('\n\nfunction paintMonitor')[0];
const elements={};const el=id=>elements[id]??=( {disabled:false,hidden:true,textContent:'',click(){this.clicked=true}} );
const ctx=vm.createContext({el,nativeRead:async()=> 'OOM https://secret.example/path',URL:{createObjectURL(){return 'blob:test'},revokeObjectURL(){}},Blob,document:{createElement:()=>({click(){ctx.downloaded=true}})},setTimeout:f=>f()});
vm.runInContext("let oomEvidence='';"+source,ctx);
(async()=>{await el('oom-load').onclick();assert.match(el('oom-output').textContent,/\[链接已隐藏\]/);assert.equal(el('oom-download').disabled,false);el('oom-download').onclick();assert(ctx.downloaded);console.log('OOM monitor read, redaction and download passed')})().catch(e=>{console.error(e);process.exit(1)});
