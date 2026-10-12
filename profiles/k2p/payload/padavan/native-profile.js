// Keep subscription strategies/rules; router listeners and DNS stay local.
// This module has no network requests or persistent state.
function buildNativeSubscription(source,base,main,oldNodes=[],policies=[]){
 const copy=x=>JSON.parse(JSON.stringify(x));source=copy(source);
 if(!Array.isArray(source.outbounds)||!source.route||!Array.isArray(source.route.rules))throw Error('完整 sing-box 订阅缺少策略组或规则');
 if(!base?.dns||!Array.isArray(base.inbounds))throw Error('无法读取本机 DNS 与接管配置，当前配置保留');
 const identity=n=>n?.server&&n.server_port&&n.type?JSON.stringify([n.type,String(n.server).toLowerCase(),Number(n.server_port),n.password??'',n.uuid??'',n.method??'',n.username??'',n.protocol??'',n.obfs??'']):'';
 const previous=new Map(),incoming=new Map(),renames=new Map(),warnings=[];
 for(const n of oldNodes){const k=identity(n);if(k)previous.set(k,[...(previous.get(k)||[]),n.tag])}
 for(const n of source.outbounds){const k=identity(n);if(k)incoming.set(k,(incoming.get(k)||0)+1)}
 for(const n of source.outbounds){const names=previous.get(identity(n));if(names?.length===1&&incoming.get(identity(n))===1&&n.tag!==names[0])renames.set(n.tag,names[0])}
 function rewrite(value){if(Array.isArray(value))return value.map(rewrite);if(!value||typeof value!=='object')return value;for(const [key,item]of Object.entries(value)){if(['tag','outbound','final','default','detour'].includes(key)&&typeof item==='string')value[key]=renames.get(item)||item;else if(key==='outbounds'&&Array.isArray(item)&&item.every(n=>typeof n==='string'))value[key]=item.map(n=>renames.get(n)||n);else value[key]=rewrite(item)}return value}
 source=rewrite(source);let out=source.outbounds;
 if(out.some(n=>typeof n.tag!=='string'||!n.tag||/[\r\n\t]/.test(n.tag))||new Set(out.map(n=>n.tag)).size!==out.length)throw Error('订阅节点或策略组名称无效/重复，当前配置保留');
 const dnsTags=new Set(out.filter(n=>n.type==='dns').map(n=>n.tag));out=out.filter(n=>n.type!=='dns');
 const tags=new Set(out.map(n=>n.tag)),nodes=out.filter(n=>n.server),groups=out.filter(n=>['selector','urltest'].includes(n.type));
 if(!nodes.length||nodes.length>500)throw Error('完整订阅须包含 1 至 500 个兼容节点');
 if(!tags.has('direct'))out.push({type:'direct',tag:'direct'});tags.add('direct');
 if(!tags.has('REJECT')&&(groups.some(g=>g.outbounds?.includes('REJECT'))||JSON.stringify(source.route).includes('\"outbound\":\"REJECT\"'))){out.push({type:'block',tag:'REJECT'});tags.add('REJECT');warnings.push('补充转换结果引用的 REJECT 拒绝出口');}
 const entry=source.route.final||source.outbounds[0]?.tag;
 const proxyEntry=groups.find(g=>g.tag===entry)?.tag||groups.find(g=>g.type==='selector')?.tag||nodes[0].tag;
 const oldByTag=new Map(oldNodes.map(n=>[n.tag,n]));let prior=main,automatic=false,seen=new Set();
 function retainGroup(tag,chain=new Set()){
  if(tags.has(tag))return true;
  const old=oldByTag.get(tag);if(!old?.outbounds||tag===main||tag==='GLOBAL'||tag.startsWith('分流/')||chain.has(tag)||chain.size>=16)return false;
  const next=new Set(chain);next.add(tag);const members=old.outbounds.filter(t=>t!==main&&t!=='GLOBAL'&&t!==proxyEntry&&retainGroup(t,next));
  if(!members.length)return false;const group=copy(old);group.outbounds=members;
  if(group.default&&!members.includes(group.default))group.default=members[0];
  out.push(group);tags.add(tag);warnings.push('保留原策略组 '+tag+' 作为兼容组');return true;
 }
 const priorGroup=oldByTag.get(main)?.default;
 while(oldByTag.get(prior)?.outbounds&&!seen.has(prior)){seen.add(prior);const old=oldByTag.get(prior);automatic=automatic||old.type==='urltest';prior=old.default||old.outbounds[0]}
 for(const g of groups.filter(g=>g.type==='selector')){
  const saved=oldByTag.get(g.tag)?.default;
  if(saved&&g.outbounds.includes(saved))g.default=saved;
  else if(g.tag===proxyEntry&&saved&&oldByTag.get(saved)?.outbounds&&retainGroup(saved)){if(!g.outbounds.includes(saved))g.outbounds.push(saved);g.default=saved;}
  else if(g.tag===proxyEntry&&priorGroup&&priorGroup!==g.tag&&retainGroup(priorGroup)){
   if(!g.outbounds.includes(priorGroup))g.outbounds.push(priorGroup);g.default=priorGroup;
  }
  else if(g.tag===proxyEntry&&!automatic&&g.outbounds.includes(prior))g.default=prior;
 }
 // Keep the panel API/DNS alias without rewriting the subscription's final.
 if(!tags.has(main)){out.push({type:'selector',tag:main,outbounds:[proxyEntry],default:proxyEntry});tags.add(main)}
 if(!tags.has('GLOBAL')){out.push({type:'selector',tag:'GLOBAL',outbounds:[main,'direct'],default:main});tags.add('GLOBAL')}
 const route=copy(source.route);route.rules=route.rules.filter(r=>!r.clash_mode&&!r.ip_is_private).map(r=>dnsTags.has(r.outbound)?Object.assign(Object.fromEntries(Object.entries(r).filter(([k])=>k!=='outbound')),{action:'hijack-dns'}):r);
 delete route.geoip;delete route.geosite;
 // All remote rule sets below become verified local files; the converter
 // HTTP client is not used by the router and is unavailable in sing-box 1.12.
 delete route.default_http_client;
 if(source.route.geoip||source.route.geosite||JSON.stringify(route.rules).match(/"geo(?:ip|site)":/))throw Error('订阅仍使用已移除的 GeoIP/GeoSite 字段，请转换为 sing-box rule-set');
 const resources=[];const sourceSets=route.rule_set||[];
 if(!Array.isArray(sourceSets)||sourceSets.length>16)throw Error('规则资源超过 K2P 的 16 个资源上限，请使用精简模板');
 route.rule_set=sourceSets.map(s=>{
  if(s.type==='inline')return s;
  if(s.type==='local'&&s.path==='/tmp/ShellCrash/ruleset/cn.srs')return s;
  if(s.type!=='remote'||!['binary','source'].includes(s.format)||typeof s.url!=='string'||!/^https?:\/\/[^\s\r\n\t]+$/.test(s.url)||s.url.length>2048)throw Error('订阅包含无法验证的本地或远程规则资源：'+s.tag);
  const index=resources.length;resources.push({index,format:s.format,url:s.url});return{type:'local',tag:s.tag,format:s.format,path:'@@rs-'+index+'@@'};
 });
 // Local cn is needed by router DNS. Avoid colliding with a provider's cn tag.
 const cn=base.route?.rule_set?.find(s=>s.tag==='cn');
 if(cn){if(route.rule_set.some(s=>s.tag==='cn'&&JSON.stringify(s)!==JSON.stringify(cn)))throw Error('订阅 cn 资源与本机 DNS 资源冲突，请更换模板');if(!route.rule_set.some(s=>s.tag==='cn'))route.rule_set.push(copy(cn))}
 route.default_domain_resolver=base.route?.default_domain_resolver||base.dns.servers?.find(s=>s.tag==='dns-direct')?.tag||base.dns.servers?.[0]?.tag;if(!route.default_domain_resolver)throw Error('本机默认 DNS 解析器缺失，当前配置保留');route.final=entry||main;
 const guards=[{inbound:'dns-in',action:'hijack-dns'},{ip_is_private:true,outbound:'direct'},{clash_mode:'Direct',outbound:'direct'},{clash_mode:'Global',outbound:'GLOBAL'}];
 const localPolicy=policies.map(r=>{const row={...r};if(!retainGroup(row.target)&&!oldNodes.some(n=>n.tag===row.target&&n.tag.startsWith('分流/')&&n.outbounds)){warnings.push(row.domain+' 的旧目标已不存在，恢复默认代理');row.target=main}return row});
 const owned=new Set(localPolicy.map(r=>r.target).filter(t=>t.startsWith('分流/')));
 for(const name of owned){if(!tags.has(name)){const old=oldNodes.find(n=>n.tag===name);let target=old?.default||main;if(!tags.has(target))target=main;out.push({type:'selector',tag:name,outbounds:[main,...nodes.map(n=>n.tag)],default:target});tags.add(name)}}
 // policy_merge.awk compiles the actual custom rule targets transactionally.
 route.rules=[...guards,...route.rules];
 for(const group of out.filter(n=>n.outbounds)){if(!group.outbounds.length||group.outbounds.some(t=>!tags.has(t)))throw Error('订阅策略组引用不存在的节点：'+group.tag);if(group.default&&!group.outbounds.includes(group.default))delete group.default}
 function targets(rule){if(rule.outbound&&!tags.has(rule.outbound))throw Error('订阅规则引用不存在的目标：'+rule.outbound);for(const child of rule.rules||[])targets(child)}route.rules.forEach(targets);
 if(!tags.has(route.final))throw Error('订阅默认出口不存在：'+route.final);
 const payload={outbounds:out,route,_panel_resources_b64:btoa(resources.map(r=>[r.index,r.format,r.url].join('\t')).join('\n')),_panel_policy_b64:btoa(unescape(encodeURIComponent(localPolicy.map(r=>[r.kind,r.domain,r.target].join('\t')).join('\n')+(localPolicy.length?'\n':''))))};
 return{payload,count:nodes.length,groups:groups.length,ruleCount:source.route.rules.length,warnings};
}
function serializeNativeSubscription(payload){return'{\n'+Object.entries(payload).map(([k,v])=>JSON.stringify(k)+':'+JSON.stringify(v)).join(',\n')+'\n}\n'}
