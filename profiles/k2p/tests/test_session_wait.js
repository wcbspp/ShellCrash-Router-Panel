const fs=require('fs'),vm=require('vm'),assert=require('assert');
(async()=>{
 const source=fs.readFileSync('payload/padavan/manager.js','utf8');
 const read=source.slice(source.indexOf('function nativeSessionError('),source.indexOf('\nlet pendingControl='));
 const wait=source.slice(source.indexOf('async function waitJob('),source.indexOf('\nasync function service('));
 let response='{"running":true}',calls=0,timers=new Map(),id=0;
 const context={Date,AbortController,JSON,fetch:async(_,opts)=>{assert(opts.signal);calls++;return {ok:true,text:async()=>response}},setTimeout:(f,ms)=>{if(ms===2500){f();return ++id}timers.set(++id,f);return id},clearTimeout:n=>timers.delete(n),el:()=>({}),decode:x=>x,words:{}};
 vm.createContext(context);vm.runInContext(read+wait+'\nasync function syncNative(){return nativeRead("state")}\nlet pendingControl=null;',context);
 assert.equal((await vm.runInContext('nativeRead("state")',context)).running,true);
 assert.equal(timers.size,0);
 for(const html of ['<html>请先注销另一用户后再尝试登录。</html>','<!DOCTYPE html><html>Login</html>']){
  response=html;calls=0;
  await assert.rejects(vm.runInContext('waitJob("fixture","done",180000)',context),e=>e.code==='session_conflict'||e.code==='session_expired');
  assert.equal(calls,1,'session rejection must not poll/retry');assert.equal(timers.size,0);
 }
 response='<html>请先注销另一用户</html>';
 await assert.rejects(vm.runInContext('nativeRead("progress")',context),e=>e.code==='session_conflict');
 response='{"id":"fixture","phase":"done","active":false}';
 assert.equal((await vm.runInContext('waitJob("fixture")',context)).phase,'done');
 console.log('Session rejection stops job waiting after one read; valid status completes; read timers cleared');
})().catch(e=>{console.error(e);process.exit(1)});
