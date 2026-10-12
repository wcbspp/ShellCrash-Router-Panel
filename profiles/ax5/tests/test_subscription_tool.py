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
  script=(ROOT/'ax5/subscription-tool.sh').read_text().replace('T=/data/ShellCrash-tool; R=/tmp/ShellCrash',f'T={tool}; R={ram}')
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
 def test_direct_uses_native_without_touching_live_configuration(self):
  p,t,r,result=self.fixture();self.assertEqual(result.returncode,0,result.stderr);self.assertEqual((r/'subscription.raw').read_text(),(p/'fixture').read_text());self.assertEqual((t/'jsons/config.json').read_text(),'live-config-preserved');self.assertFalse([x for x in r.glob('subscription-tool.*') if x.is_dir()]);self.assertEqual(result.stdout,'')
 def test_direct_ignores_stored_conversion_and_selected_custom_server(self):
  p,t,r,result=self.fixture('direct',core_kind='meta',stored_urls=True,options={'custom':'https://custom.example.com','template':'https://rules.example.com/custom.ini'},policy='s0a1')
  self.assertEqual(result.returncode,0,result.stderr)
  requests=(p/'requests').read_text();self.assertNotIn('/sub?',requests);self.assertNotIn('converter.example.com',requests);self.assertNotIn('custom.example.com',requests)
  self.assertIn('subscription.example.com/private-fixture',requests)
  self.assertNotIn('OLD',(r/'subscription.progress').read_text());self.assertNotIn('预检',(r/'subscription-tool.log').read_text())
 def test_native_converter_uses_selected_server(self):
  p,t,r,result=self.fixture('convert');self.assertEqual(result.returncode,0,result.stderr);requests=(p/'requests').read_text();self.assertIn('converter.example.com/sub?target=singbox',requests);self.assertNotIn('other.example.com',requests)
 def test_failure_does_not_switch_converter_or_change_live_config(self):
  p,t,r,result=self.fixture('convert',True);self.assertNotEqual(result.returncode,0);self.assertNotIn('other.example.com',(p/'requests').read_text());self.assertNotIn('subscription.example.com',(r/'subscription-tool.log').read_text());self.assertNotIn('private-fixture',(r/'subscription-tool.log').read_text());self.assertIn('curl=1',(r/'subscription-tool.log').read_text());self.assertEqual((t/'jsons/config.json').read_text(),'live-config-preserved');self.assertFalse((r/'subscription.raw').exists());self.assertFalse([x for x in r.glob('subscription-tool.*') if x.is_dir()])
 def test_invalid_converter_output_never_replaces_live_config(self):
  p,t,r,result=self.fixture('convert',payload='<html>failure</html>');self.assertNotEqual(result.returncode,0);self.assertFalse((r/'subscription.raw').exists());self.assertEqual((t/'jsons/config.json').read_text(),'live-config-preserved')
 def test_k2p_automatic_ua_tracks_configured_core_version(self):
  import base64
  p,t,r,result=self.fixture('convert',platform='k2p',core_version='1.12.14');self.assertEqual(result.returncode,0,result.stderr)
  info=dict(line.split('=',1) for line in (r/'subscription-fetch.info').read_text().splitlines());self.assertEqual(base64.b64decode(info['ua_b64']).decode(),'sing-box/singbox/1.12.14')
 def test_k2p_native_generation_with_root_server_list(self):
  p,t,r,result=self.fixture('convert',platform='k2p');self.assertEqual(result.returncode,0,result.stderr);self.assertTrue((r/'sub.raw').exists());self.assertNotIn('other.example.com',(p/'requests').read_text())
 def test_http_503_reason_is_recorded_without_subscription_leak(self):
  p,t,r,result=self.fixture('convert',http=503);self.assertNotEqual(result.returncode,0);self.assertEqual((r/'subscription.error').read_text().strip(),'subscription_http_503');self.assertIn('HTTP=503',(r/'subscription-tool.log').read_text());self.assertNotIn('subscription.example.com',(r/'subscription-tool.log').read_text());self.assertNotIn('private-fixture',(r/'subscription-tool.log').read_text());self.assertEqual((t/'jsons/config.json').read_text(),'live-config-preserved')
 def test_unavailable_preflight_never_transmits_subscription(self):
  p,t,r,result=self.fixture('convert',http=503,policy='s0a1');self.assertNotEqual(result.returncode,0);requests=(p/'requests').read_text();self.assertIn('other.example.com',requests);self.assertNotIn('private-fixture',requests);self.assertNotIn('url=',requests);self.assertEqual((t/'jsons/config.json').read_text(),'live-config-preserved')
 def test_custom_service_template_and_ua_use_upstream_generator_without_other_services(self):
  p,t,r,result=self.fixture('convert',policy='s0a1',options={'custom':'https://custom.example.com','template':'https://rules.example.com/custom.ini','ua':'clash-verge/v2.4.5'})
  self.assertEqual(result.returncode,0,result.stderr);requests=(p/'requests').read_text();self.assertIn('https://custom.example.com/sub?target=singbox',requests);self.assertIn('clash-verge/v2.4.5',requests);self.assertNotIn('converter.example.com',requests);self.assertNotIn('other.example.com',requests);self.assertIn('custom.ini',requests);self.assertIn('custom_b64=',(r/'subscription-fetch.info').read_text());self.assertEqual((t/'configs/ShellCrash.cfg').read_text(),'server_link=1\nrule_link=1\n')
 def test_mihomo_provider_snapshot_uses_shellcrash_direct_ua_and_retains_template(self):
  template='proxy-providers:\n  subscription:\n    type: http\n    url: https://subscription.example.com/private-fixture\nproxy-groups:\n  - name: Native\n    type: select\n    use: [subscription]\nrules:\n  - MATCH,Native\n'
  nodes='proxies:\n  - name: AnyTLS node\n    type: anytls\n    server: test.invalid\n    port: 443\n    password: fixture\n'
  p,t,r,result=self.fixture('convert',core_kind='meta',payload=template,source_payload=nodes)
  self.assertEqual(result.returncode,0,result.stderr)
  self.assertEqual((r/'subscription.raw').read_text(),template)
  self.assertEqual((r/'subscription.nodes.raw').read_text(),nodes)
  requests=(p/'requests').read_text();self.assertNotIn('list=true',requests)
  self.assertIn('provider_source=shellcrash-direct',(r/'subscription-fetch.info').read_text())
  self.assertEqual((t/'jsons/config.json').read_text(),'live-config-preserved')
 def test_bad_custom_options_never_send_a_subscription(self):
  for options in [{'custom':'https://user:password@host.example.com'},{'ua':'safe\r\nInjected: invalid'},{'template':'https://rules.example.com/x\n401 Inject https://other.example.com'}]:
   p,t,r,result=self.fixture('convert',options=options);self.assertNotEqual(result.returncode,0);self.assertFalse((p/'requests').exists());self.assertEqual((r/'subscription.error').read_text().strip(),'subscription_options_invalid')
if __name__=='__main__' :unittest.main()
