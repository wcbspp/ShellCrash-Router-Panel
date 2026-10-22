"""Actual shared device picker logic; no device pass implied."""
import json,subprocess,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class AccessUI(unittest.TestCase):
 def test_device_selection_ip_resolves_to_mac_and_empty_switch_is_disabled(self):
  source='let proxyAccessDirty=false'+(ROOT/'shared/ui/manager.js.in').read_text().split('let proxyAccessDirty=false',1)[1]
  harness=r'''
const vm=require('node:vm'),assert=require('node:assert');
function element(){return {value:'',checked:false,disabled:false,hidden:true,children:[],append(...x){this.children.push(...x)},replaceChildren(){this.children=[]}}}
const ids=['enabled','macs','save','result','devices','devices-note','count','add','refresh'];const els=Object.fromEntries(ids.map(k=>['proxy-access-'+k,element()]));els['rules-tab']=element();
const calls=[],notes=[];const ctx={el:id=>els[id],document:{createElement:element},manageBusy:false,advancedActive:false,nativeState:{active:false,proxy_access:{available:true,enabled:false,macs_b64:''}},
 decode:x=>Buffer.from(x,'base64').toString(),confirm:()=>true,note:(...x)=>notes.push(x),pauseMeasurements(){},pauseSites(){},showService(){},
 crypto:{getRandomValues:a=>a.fill(1)},TextEncoder,
 nativeRead:async()=>({devices:[{ip:'192.168.1.20',mac:'02:11:22:33:44:55',name:'<script>bad</script>',status:'online'}]}),
 upload:async(id,kind,bytes)=>calls.push(['upload',kind,Buffer.from(bytes).toString()]),control:async(script,args)=>calls.push(['control',script,args]),waitJob:async()=>({}),syncNative:async()=>{}};
vm.createContext(ctx);vm.runInContext(SOURCE,ctx);
(async()=>{
 ctx.paintProxyAccess(ctx.nativeState);assert.equal(els['proxy-access-enabled'].disabled,true);
 await ctx.refreshAccessDevices();assert.equal(els['proxy-access-devices'].children.length,1);
 const row=els['proxy-access-devices'].children[0];assert.equal(row.children[1].children[0].textContent,'<script>bad</script>'); // text only
 els['proxy-access-macs'].value='192.168.1.20';ctx.addAccessAddress();assert.equal(els['proxy-access-enabled'].disabled,false);
 els['proxy-access-enabled'].checked=true;els['proxy-access-enabled'].onchange();await ctx.saveProxyAccess();
 assert.equal(calls[0][1],'access');assert.equal(calls[0][2],'1\n02:11:22:33:44:55\n');assert.equal(calls[1][1],'sc-access.sh');
 els['proxy-access-macs'].value='ff:ff:ff:ff:ff:ff';ctx.addAccessAddress();assert(notes.at(-1)[1]);
})().catch(e=>{console.error(e);process.exitCode=1});
'''
  result=subprocess.run(['node','-e','const SOURCE='+json.dumps(source)+';\n'+harness],text=True,capture_output=True)
  self.assertEqual(result.returncode,0,result.stderr)
 def test_entering_rules_loads_devices_once(self):
  text=(ROOT/'shared/ui/manager.js.in').read_text()
  picker='let proxyAccessDirty=false'+text.split('let proxyAccessDirty=false',1)[1]
  tabs=text.split('function showTab(tab){')[1:]
  for tab in tabs:
   show='function showTab(tab){'+tab.split('\nfunction showService()',1)[0]
   harness=r'''
const vm=require('node:vm'),assert=require('node:assert');
const items=new Map();function el(id){if(!items.has(id))items.set(id,{hidden:true,open:false,disabled:false,checked:false,classList:{toggle(){}},replaceChildren(){},append(){}});return items.get(id)}
let reads=0;const noop=()=>{};
const ctx={el,activeTab:'nodes',manageBusy:false,advancedActive:false,siteBusy:false,nativeState:{proxy_access:{available:false}},document:{createElement:()=>({})},decode:()=>'',pauseMeasurements:noop,autoMeasure:noop,loadPolicy:noop,loadInspection:noop,
 nativeRead:async()=>{reads++;return{devices:[]}}};
vm.createContext(ctx);vm.runInContext(SOURCE,ctx);
(async()=>{ctx.showTab('rules');await new Promise(r=>setImmediate(r));assert.equal(reads,1);ctx.showTab('rules');await new Promise(r=>setImmediate(r));assert.equal(reads,1)})().catch(e=>{console.error(e);process.exitCode=1});
'''
   result=subprocess.run(['node','-e','const SOURCE='+json.dumps(picker+'\n'+show)+';\n'+harness],text=True,capture_output=True)
   self.assertEqual(result.returncode,0,result.stderr)
