const fs=require('fs'),path=require('path'),vm=require('vm'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..'),file=fs.existsSync(path.join(root,'ui/manager.js'))?'ui/manager.js':'payload/padavan/manager.js',text=fs.readFileSync(path.join(root,file),'utf8');
function setup(){let resolve,reads=0;const fields={'dns-mode':{value:'mix'},'dns-filter':{value:''}},errors=[];
 const c=vm.createContext({nativeState:{dns_mode:'mix'},el:k=>fields[k],nativeRead:()=>{reads++;return new Promise(r=>resolve=r)},indexDNS(){},note:m=>errors.push(m)});
 vm.runInContext("let dnsLoaded=false,dnsDirty=false,dnsBaseline=null,dnsRevision=0,dnsLoadPromise=null;"+text.match(/function updateDNSDirty\(\)[\s\S]*?(?=function indexDNS)/)[0],c);
 return {c,fields,errors,readCount:()=>reads,resolve:s=>resolve(s),dirty:()=>vm.runInContext('dnsDirty',c),changed:()=>vm.runInContext('dnsRevision++;updateDNSDirty()',c)};
}
(async()=>{let x=setup(),p=x.c.loadDNS();x.resolve('# fixture\r\nexample.com\r\n');await p;assert(!x.dirty());x.fields['dns-mode'].value='redir_host';x.changed();assert(x.dirty());x.fields['dns-mode'].value='mix';x.changed();assert(!x.dirty(),'reverting mode must release advanced-panel draft guard');x.fields['dns-filter'].value+='new.example\n';x.changed();assert(x.dirty());x.fields['dns-filter'].value='# fixture\nexample.com\n';x.changed();assert(!x.dirty());
 x=setup();p=x.c.loadDNS();const second=x.c.loadDNS();assert.equal(x.readCount(),1);x.fields['dns-filter'].value='my pending draft';x.changed();x.resolve('server filter\n');await Promise.all([p,second]);assert.equal(x.fields['dns-filter'].value,'my pending draft','late read must preserve user edits');assert(x.dirty());console.log('DNS draft baseline: reverting mode/filter clears dirty; coalesced loading preserves edits');
})().catch(e=>{console.error(e);process.exitCode=1});
