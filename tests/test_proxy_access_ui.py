"""Exercise the actual shared controls without a device or browser network."""
import subprocess,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class AccessUI(unittest.TestCase):
 def test_actual_ui_draft_confirmation_and_authenticated_upload(self):
  source=(ROOT/'shared/ui/manager.js.in').read_text().split('let proxyAccessDirty=false;',1)[1]
  harness=r'''
const vm=require('node:vm'),assert=require('node:assert');
const elements={};for(const id of ['proxy-access-enabled','proxy-access-macs','proxy-access-save','proxy-access-result'])elements[id]={value:'',checked:false,disabled:false};
const calls=[],notes=[];let confirmed=false;
const ctx={el:id=>elements[id],manageBusy:false,advancedActive:false,nativeState:{active:false,proxy_access:{enabled:false,macs_b64:''}},
 decode:x=>Buffer.from(x,'base64').toString(),confirm:()=>confirmed,note:(...x)=>notes.push(x),pauseMeasurements(){},pauseSites(){},showService(){},
 crypto:{getRandomValues:a=>a.fill(1)},TextEncoder,
 upload:async(id,kind,bytes)=>calls.push(['upload',kind,Buffer.from(bytes).toString()]),
 control:async(script,args)=>calls.push(['control',script,args]),waitJob:async()=>({}),syncNative:async()=>{}};
vm.createContext(ctx);vm.runInContext('let proxyAccessDirty=false;'+SOURCE,ctx);
(async()=>{
 ctx.paintProxyAccess(ctx.nativeState);assert.equal(elements['proxy-access-save'].disabled,true);
 elements['proxy-access-enabled'].checked=true;elements['proxy-access-enabled'].oninput();
 await ctx.saveProxyAccess();assert.equal(calls.length,0); // Empty-list confirmation cancelled.
 confirmed=true;elements['proxy-access-macs'].value='ff:ff:ff:ff:ff:ff';
 await ctx.saveProxyAccess();assert.equal(calls.length,0);assert(notes.at(-1)[1]);
 elements['proxy-access-macs'].value='02:11:22:33:44:55';
 await ctx.saveProxyAccess();assert.equal(calls[0][1],'access');assert.equal(calls[0][2],'1\n02:11:22:33:44:55\n');
 assert.equal(calls[1][1],'sc-access.sh');
 elements['proxy-access-macs'].value='02:aa:bb:cc:dd:ee';elements['proxy-access-macs'].oninput();
 ctx.paintProxyAccess(ctx.nativeState);assert.equal(elements['proxy-access-macs'].value,'02:aa:bb:cc:dd:ee');
})().catch(e=>{console.error(e);process.exitCode=1});
'''
  js='const SOURCE='+__import__('json').dumps(source)+';\n'+harness
  result=subprocess.run(['node','-e',js],text=True,capture_output=True)
  self.assertEqual(result.returncode,0,result.stderr)
