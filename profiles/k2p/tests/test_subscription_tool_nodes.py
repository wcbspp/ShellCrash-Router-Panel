"""Native subscription generation must stay isolated and never retry another converter."""
import os,subprocess,tempfile,unittest,shutil,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class SubscriptionTests(unittest.TestCase):
 def fixture(self,mode='direct',failure=False,http=None,policy='s0a0',payload=None,platform='ax5',options=None,core_version=None,core_kind=None,source_payload=None,stored_urls=False):
  td=tempfile.TemporaryDirectory();self.addCleanup(td.cleanup);p=Path(td.name);tool=p/'tool';ram=p/'ram';ram.mkdir();bin=p/'bin';bin.mkdir()
  # Actual upstream 1.9.4 generator and dependencies, shipped in the public package.
  subprocess.run(['tar','-xzf',str(ROOT/'vendor/ShellCrash-1.9.4.tar.gz'),'-C',str(p)],check=True)
  tool.mkdir();shutil.move(str(p/'libs'),str(tool/'libs'));shutil.move(str(p/'starts'),str(tool/'starts'))
  (tool/'configs').mkdir();(tool/'configs/ShellCrash.cfg').write_text('server_link=1\nrule_link=1\n'+('crashcore='+core_kind+'\n' if core_kind else '')+('core_v='+core_version+'\n' if core_version else ''))
  if stored_urls:
   with (tool/'configs/ShellCrash.cfg').open('a') as f:f.write('Url=old-private-subscription\nHttps=old-direct-subscription\n')
  (ram/'subscription.progress').write_text('OLD converter preflight')
  (tool/'configs/servers.list').write_text('401 First https://converter.example.com user_agent\n402 Second https://other.example.com user_agent\n501 Rule https://rules.example.com/base\n')
  (ram/'upload-source').write_text('https://subscription.example.com/private-fixture')
  (tool/'jsons').mkdir();(tool/'jsons/config.json').write_text('live-config-preserved')
  script=(ROOT/'payload/starts/subscription_tool.sh').read_text().replace('T=/data/ShellCrash-tool; R=/tmp/ShellCrash',f'T={tool}; R={ram}')
  script=script.replace('T=/etc/storage/ShellCrash; R=/tmp/sc-admin',f'T={tool}; R={ram}')
  (tool/'starts/panel_env.sh').write_text('PANEL_LAN_IP=192.168.31.1\n')
  if options:
   import base64
   envelope=(ram/'upload-source').read_text()+'\n'+''.join(k+'='+base64.b64encode(v.encode()).decode()+'\n' for k,v in options.items())
   (ram/'upload-source').write_text(envelope)
  (ram/'native-source').write_text((ram/'upload-source').read_text())
  if platform=='k2p':shutil.move(str(tool/'configs/servers.list'),str(tool/'servers.list'))
  f=p/'run.sh';f.write_text(script)
  (p/'fixture').write_text(payload if payload is not None else json.dumps({'outbounds':[{'type':'trojan','tag':'香港01','server':'example.com','server_port':443,'password':'fixture'}]}))
  if source_payload is not None:(p/'source-fixture').write_text(source_payload)
  curl=bin/'curl';curl.write_text('''#!/usr/bin/env python3
import sys,os,shutil
from pathlib import Path
p=Path(os.environ['TEST_ROOT']);a=sys.argv[1:]
with (p/'requests').open('a') as f:f.write(next(x for x in a if x.startswith('https://'))+'\\n')
if os.environ.get('TEST_HTTP'):print(os.environ['TEST_HTTP'],end='');sys.exit(22)
if os.environ.get('TEST_FAIL'):sys.exit(1)
url=next(x for x in a if x.startswith('https://'))
source=p/'source-fixture' if url.startswith('https://subscription.example.com/') and (p/'source-fixture').exists() else p/'fixture'
shutil.copyfile(source,a[a.index('-o')+1])
if '-w' in a:print('200',end='')
''');curl.chmod(0o700)
  env=dict(os.environ,PATH=str(bin)+os.pathsep+os.environ['PATH'],TEST_ROOT=str(p))
  if failure:env['TEST_FAIL']='1'
  if http:env['TEST_HTTP']=str(http)
  result=subprocess.run(['sh',str(f),platform,mode,policy],env=env,capture_output=True,text=True)
  return p,tool,ram,result
 def test_conversion_keeps_singbox_template_and_tool_settings(self):
  p,t,r,result=self.fixture('convert',platform='k2p',options={'template':'https://rules.example.com/large.ini','custom':'https://custom.example.com'},core_kind='meta')
  self.assertEqual(result.returncode,0,result.stderr)
  requests=(p/'requests').read_text();self.assertIn('https://custom.example.com/sub?target=singbox',requests)
  self.assertIn('large.ini',requests);self.assertIn('rules.example.com',requests)
  self.assertEqual((t/'configs/ShellCrash.cfg').read_text(),'server_link=1\nrule_link=1\ncrashcore=meta\n')
  self.assertTrue((r/'sub.raw').exists())
 def test_direct_never_preflights_or_contacts_a_converter(self):
  p,t,r,result=self.fixture('direct',platform='k2p',options={'custom':'https://custom.example.com','template':'https://rules.example.com/large.ini'})
  self.assertEqual(result.returncode,0,result.stderr)
  requests=(p/'requests').read_text();self.assertNotIn('/sub?',requests);self.assertNotIn('custom.example.com',requests)
  self.assertNotIn('rules.example.com',requests);self.assertIn('subscription.example.com',requests)
if __name__=='__main__':unittest.main()
