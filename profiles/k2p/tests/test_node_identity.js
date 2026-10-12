const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const s=fs.readFileSync(require('node:path').join(__dirname,'../payload/padavan/manager.js'),'utf8'),code=s.slice(s.indexOf('function retainSubscriptionNodeNames('),s.indexOf('function parseSubscription('));const c=vm.createContext({});vm.runInContext(code,c);const f=c.retainSubscriptionNodeNames;
const before={type:'anytls',tag:'🇹🇼 台湾01',server:'NODE.EXAMPLE',server_port:443,password:'fixture'},incoming={...before,server:'node.example',tag:'台湾01'};
assert.equal(f([incoming],[before])[0].tag,before.tag);assert.equal(incoming.tag,'台湾01');
for(const change of [{password:'changed'},{server_port:444},{type:'trojan'},{server:'other.example'}])assert.equal(f([{...incoming,...change}],[before])[0].tag,'台湾01');
assert.equal(f([incoming],[before,{...before,tag:'another alias'}])[0].tag,'台湾01');
assert.throws(()=>f([incoming,{...incoming,tag:before.tag,server:'different.example'}],[before]),/重复/);
console.log('Node identity: emoji rename, immutable input, endpoint/auth/protocol changes, aliases and collision guard passed');
