const fs=require('fs'),path=require('path'),vm=require('vm'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..'),text=fs.readFileSync(path.join(root,fs.existsSync(path.join(root,'ui/manager.js'))?'ui/manager.js':'payload/padavan/manager.js'),'utf8');
const c=vm.createContext({label:x=>x});vm.runInContext(text.match(/function trafficBytes\(value\)[\s\S]*?(?=function paintTraffic)/)[0]+text.match(/function inspectRows\(kind,data\)[\s\S]*?(?=function cancelInspection)/)[0],c);
let r=c.inspectRows('connections',{connections:[{metadata:{host:'fixture.example',sourceIP:'192.0.2.2',sourcePort:'1234',destinationIP:'203.0.113.7',destinationPort:'443',network:'tcp'},upload:4096,download:8192,chains:['direct'],rule:'DomainSuffix',rulePayload:'fixture.example'}]})[0];
assert.equal(r.title,'fixture.example');assert(r.detail.includes('192.0.2.2:1234 → 203.0.113.7:443'));assert(r.detail.includes('↑ 4.0 KB / ↓ 8.0 KB'));assert(r.detail.includes('direct'));assert(r.detail.includes('DomainSuffix / fixture.example'));
r=c.inspectRows('connections',{connections:[{metadata:{destinationIP:'203.0.113.9'},upload:0,download:0}]})[0];assert.equal(r.title,'203.0.113.9');assert(r.detail.includes('↑ 0 B / ↓ 0 B'));
r=c.inspectRows('connections',{connections:[{metadata:{},upload:-1}]})[0];assert.equal(r.title,'未知目标');assert(r.detail.includes('待统计'));
assert.deepEqual(Array.from(c.inspectRows('connections',{connections:[]})),[]);
console.log('active connection rows: client and destination endpoint, protocol, route and per-connection totals; missing data is never invented');
