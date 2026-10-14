const fs=require('fs'),vm=require('vm'),assert=require('assert'),path=require('path');
const root=path.resolve(__dirname,'..'),file=fs.existsSync(path.join(root,'ui/sites.js'))?'ui/sites.js':'payload/padavan/sites.js';
const source=fs.readFileSync(path.join(root,file),'utf8');
const helpers=source.slice(source.indexOf('function siteProbeTarget('),source.indexOf('function paintSites('));
const results=new Map([['google',{state:'ok',delay:12}]]);let paused=0,painted=0;
const c=vm.createContext({proxyMode:'rule',mainName:()=> 'main',resolvedNode:n=>'leaf-'+n,siteResults:results,pauseSites:()=>paused++,paintSites:()=>painted++});
vm.runInContext("let siteLastTime=123,siteLastNode='old';"+helpers,c);
assert.equal(c.siteProbeTarget({route:'proxy-main'}),'main');
c.proxyMode='direct';assert.equal(c.siteProbeTarget({route:'proxy-main'}),'direct');
c.proxyMode='global';assert.equal(c.siteProbeTarget({route:'proxy-main'}),'GLOBAL');assert.equal(c.siteProbeTarget({route:'direct'}),'GLOBAL','global mode must use proxy for domestic targets too');
c.invalidateSiteResults();assert.equal(results.size,0);assert.equal(paused,1);assert.equal(painted,1);assert.equal(vm.runInContext('siteLastTime',c),0);
assert(source.includes('encodeURIComponent(siteProbeTarget(s))'),'actual probe API must use mode-aware target');
console.log('website probe targets follow mode and stale successful results are invalidated');

assert.equal(c.siteProbeResult({delay:12,http:200}).state,'ok');assert.equal(c.siteProbeResult({delay:12,http:403}).state,'ok');assert.equal(c.siteProbeResult({delay:12,http:503}).state,'ok');assert.equal(c.siteProbeResult({delay:12}).state,'ok');assert.equal(c.siteProbeResult({delay:0,tls:60}).reason,'TLS 验证失败');assert.equal(c.siteProbeFailure({status:400,message:'bad endpoint'}).reason,'接口错误 400');assert.equal(c.siteProbeFailure({name:'AbortError',message:'aborted'}).reason,'检测超时');assert.equal(c.siteProbeResult({delay:12,http:429}).state,'ok');assert.equal(c.siteProbeResult({delay:12,http:403,tls:60}).state,'failed');assert.equal(c.siteProbeResult({delay:NaN,http:403}).state,'failed');assert.equal(c.siteProbeResult({delay:-1,http:200}).state,'failed');console.log('network connectivity: 403/429/503 are reachable; timeout, malformed timing, TLS and API failures remain failures');

// A Cloudflare-style response must render as reachable, without an amber access error.
{
 const classes=new Set(['warn']),label={},delay={},card={classList:{toggle(k,v){v?classes.add(k):classes.delete(k)},remove(k){classes.delete(k)}},querySelector:k=>k==='.site-result'?label:delay};
 const elements={'site-openai':card,'sites-run':{},'site-route':{},'sites-summary':{}};
 const results=new Map(),v=vm.createContext({el:id=>elements[id],sites:[{id:'openai',url:'https://chatgpt.com/favicon.ico'}],siteResults:results,siteBusy:false,manageBusy:false,nativeState:{},running:true,resolvedNode:()=> 'same',mainName:()=> 'main',proxyMode:'rule'});
 vm.runInContext('let siteLastTime=1,siteLastNode="same";'+helpers+source.slice(source.indexOf('function paintSites('),source.indexOf('function initializeSites(')),v);
 results.set('openai',v.siteProbeResult({delay:1257,http:403,tls:0}));v.paintSites();assert(classes.has('good'));assert(!classes.has('warn'));assert.equal(label.textContent,'网络可达');assert.equal(delay.textContent,'1257 ms');assert(elements['sites-summary'].textContent.includes('1 个可达'));assert(!elements['sites-summary'].textContent.includes('HTTP 错误'));
 results.set('openai',v.siteProbeResult({delay:0,tls:60}));v.paintSites();assert(classes.has('bad'));assert(!classes.has('good'));assert.equal(label.textContent,'TLS 验证失败');
 console.log('connectivity card: HTTP rejection renders green reachability/time, TLS failure renders failure');
}
