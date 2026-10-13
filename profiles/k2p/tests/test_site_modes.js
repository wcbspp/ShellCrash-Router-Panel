const fs=require('fs'),vm=require('vm'),assert=require('assert'),path=require('path');
const root=path.resolve(__dirname,'..'),file=fs.existsSync(path.join(root,'ui/sites.js'))?'ui/sites.js':'payload/padavan/sites.js';
const source=fs.readFileSync(path.join(root,file),'utf8');
const helpers=source.slice(source.indexOf('function siteProbeTarget('),source.indexOf('function paintSites('));
const results=new Map([['google',{state:'ok',delay:12}]]);let paused=0,painted=0;
const c=vm.createContext({proxyMode:'rule',mainName:()=> 'main',resolvedNode:n=>'leaf-'+n,siteResults:results,pauseSites:()=>paused++,paintSites:()=>painted++});
vm.runInContext("let siteLastTime=123,siteLastNode='old';"+helpers,c);
assert.equal(c.siteProbeTarget({route:'proxy-main'}),'main');
c.proxyMode='direct';assert.equal(c.siteProbeTarget({route:'proxy-main'}),'direct');
c.proxyMode='global';assert.equal(c.siteProbeTarget({route:'proxy-main'}),'GLOBAL');assert.equal(c.siteProbeTarget({route:'direct'}),'direct','explicit domestic direct probe remains a separate test');
c.invalidateSiteResults();assert.equal(results.size,0);assert.equal(paused,1);assert.equal(painted,1);assert.equal(vm.runInContext('siteLastTime',c),0);
assert(source.includes('encodeURIComponent(siteProbeTarget(s))'),'actual probe API must use mode-aware target');
console.log('website probe targets follow mode and stale successful results are invalidated');

assert.equal(c.siteProbeResult({delay:12,http:200}).state,'ok');assert.equal(c.siteProbeResult({delay:12,http:403}).state,'http-error');assert.equal(c.siteProbeResult({delay:12,http:503}).state,'http-error');assert.equal(c.siteProbeResult({delay:12}).state,'ok');assert.equal(c.siteProbeResult({delay:0,tls:60}).reason,'TLS 验证失败');assert.equal(c.siteProbeFailure({status:400,message:'bad endpoint'}).reason,'接口错误 400');assert.equal(c.siteProbeFailure({name:'AbortError',message:'aborted'}).reason,'检测超时');console.log('site failures distinguish API errors, timeout/TLS, HTTP access errors and successful responses');
