#!/usr/bin/env python3
"""Prepare a private, line-normalized sing-box profile for the Padavan panel."""
import argparse,json,re,secrets,ipaddress
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--input',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--lan-ip',required=True);p.add_argument('--secret-file',type=Path,required=True);p.add_argument('--cn-list',type=Path,required=True)
a=p.parse_args();ipaddress.IPv4Address(a.lan_ip)
data=json.loads(a.input.read_text());nodes=data if isinstance(data,list) else data.get('outbounds',[])
nodes=[n for n in nodes if n.get('server') and n.get('type') not in ['direct','block','dns','selector','urltest']]
if not nodes or len(nodes)>500:raise SystemExit('需要1至500个独立代理节点')
if any(n.get('detour') for n in nodes):raise SystemExit('不支持链式detour；请使用独立节点配置')
seen=set();groups={};countries=['香港','台湾','新加坡','日本','美国','韩国','英国','德国','法国','加拿大','澳大利亚']
for n in nodes:
 tag=n.get('tag','');
 if not tag or tag in seen or tag in ['proxy-main','direct'] or tag.startswith('地区/'):raise SystemExit('节点名称缺失、重复或与管理组冲突')
 seen.add(tag);country=next((x for x in countries if x in tag),'其他');groups.setdefault('地区/'+country,[]).append(tag)
cn=[str(ipaddress.IPv4Network(s.strip(),strict=True)) for s in a.cn_list.read_text().splitlines() if s.strip() and not s.startswith('#')]
secret=a.secret_file.read_text().strip() if a.secret_file.exists() else secrets.token_hex(24)
if not secret:raise SystemExit('管理密钥不能为空')
a.secret_file.parent.mkdir(parents=True,exist_ok=True);a.secret_file.write_text(secret+'\n');a.secret_file.chmod(0o600)
bounds=[{'type':'selector','tag':'proxy-main','outbounds':list(groups),'default':next(iter(groups))}]+[{'type':'selector','tag':tag,'outbounds':names,'default':names[0]} for tag,names in groups.items()]+[{'type':'direct','tag':'direct'}]+nodes
profile={'log':{'level':'warn','timestamp':True,'output':'/tmp/ShellCrash/core.log'},'dns':{'servers':[{'type':'udp','tag':'dns-direct','server':'223.5.5.5'},{'type':'tcp','tag':'dns-proxy','server':'8.8.8.8','detour':'proxy-main'},{'type':'fakeip','tag':'dns-fake','inet4_range':'198.18.0.0/15'}],'rules':[{'rule_set':['cn'],'server':'dns-direct'},{'query_type':['A'],'server':'dns-fake'},{'query_type':['AAAA'],'action':'reject'}],'final':'dns-proxy','strategy':'ipv4_only'},'inbounds':[{'type':'mixed','tag':'mixed-in','listen':a.lan_ip,'listen_port':7890},{'type':'redirect','tag':'redir-in','listen':'0.0.0.0','listen_port':7892},{'type':'direct','tag':'dns-in','listen':'0.0.0.0','listen_port':1053}], 'outbounds':bounds,'route':{'rules':[{'inbound':'dns-in','action':'hijack-dns'},{'ip_is_private':True,'outbound':'direct'},{'rule_set':['cn'],'outbound':'direct'},{'ip_cidr':cn,'outbound':'direct'}],'rule_set':[{'type':'local','tag':'cn','format':'binary','path':'/tmp/ShellCrash/ruleset/cn.srs'}],'final':'proxy-main','default_domain_resolver':'dns-direct'},'experimental':{'cache_file':{'enabled':True,'path':'/tmp/ShellCrash/fakeip.db','store_fakeip':True},'clash_api':{'external_controller':a.lan_ip+':9999','secret':secret,'external_ui':'/tmp/ShellCrash/ui'}}}
a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text('{\n'+',\n'.join(json.dumps(k)+':'+json.dumps(v,ensure_ascii=False,separators=(',',':')) for k,v in profile.items())+'\n}\n');a.output.chmod(0o600)
print('已生成私有配置；节点:',len(nodes),'地区:',len(groups),'国内网段:',len(cn),'。密钥未输出。')
