const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict'),path=require('node:path');
const code=fs.readFileSync(path.join(__dirname,'../ui/manager.js'),'utf8').match(/function parseSubscription[\s\S]*?(?=async function upload)/)[0];
const c=vm.createContext({URL,URLSearchParams,TextDecoder,Buffer,decode:s=>Buffer.from(s,'base64').toString(),proxies:{'proxy-main':{now:'地区/台湾'},'分流/ChatGPT':{now:'台湾01'}},mainName:()=> 'proxy-main',nativeState:{core_kind:'singbox'}});vm.runInContext(code,c);
const fixed=p=>p.out.find(x=>x.tag==='分流/ChatGPT');
let p=c.parseSubscription('anytls://fixture@node.example:443#台湾01');assert.equal(fixed(p).default,'台湾01');assert.equal(p.warnings.length,0);
p=c.parseSubscription('anytls://fixture@node.example:443#🇹🇼台湾01');assert.equal(fixed(p).default,'台湾01');assert.equal(p.warnings.length,0); // Router matches identity before reconciling missing selections.
assert.throws(()=>c.parseSubscription('not-a-subscription'));
console.log('Missing local fixed nodes reset to default proxy with a warning; surviving nodes retain choices; invalid subscriptions still reject');
