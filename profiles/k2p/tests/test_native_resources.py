"""Bounded native rule assets and candidate merge, using real shell/curl."""
import base64,hashlib,json,os,shutil,subprocess,tempfile,threading,unittest
from pathlib import Path
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
SOURCE=Path(__file__).resolve().parents[1]/'payload/starts'

class Server(BaseHTTPRequestHandler):
    def log_message(self,*args):pass
    def do_GET(self):
        self.server.calls.append(self.path);body=self.server.payload
        self.send_response(200);self.send_header('Content-Length',str(len(body)));self.end_headers()
        try:self.wfile.write(body)
        except(BrokenPipeError,ConnectionResetError):pass

class NativeResources(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name);self.c=self.root/'persist';self.d=self.root/'admin';self.ram=self.root/'ram'
        for p in [self.c/'starts',self.c/'configs',self.c/'jsons',self.d,self.ram/'ruleset']:p.mkdir(parents=True,exist_ok=True)
        (self.root/'meminfo').write_text('MemAvailable: 40960 kB\n')
        for name in ['remote.sh','webdav.sh','policy_merge.awk']:shutil.copy(SOURCE/name,self.c/'starts'/name)
        self.helper=self.root/'helper.sh';self.helper.write_text((SOURCE/'native_profile.sh').read_text().replace('/tmp/ShellCrash',str(self.ram)).replace('/proc/meminfo',str(self.root/'meminfo')))
        self.server=ThreadingHTTPServer(('127.0.0.1',0),Server);self.server.calls=[];self.server.payload=b'rules fixture';self.thread=threading.Thread(target=self.server.serve_forever,daemon=True);self.thread.start();self.url='http://127.0.0.1:%s/rules.srs'%self.server.server_port
        self.env=dict(os.environ,C=str(self.c),D=str(self.d),PANEL_LAN_IP='127.0.0.1')
    def tearDown(self):self.server.shutdown();self.server.server_close();self.thread.join();self.tmp.cleanup()
    def run_shell(self,cmd):return subprocess.run(['sh','-c','. "'+str(self.helper)+'"; '+cmd],env=self.env,capture_output=True,text=True,timeout=20)
    def prepare(self,rows):
        (self.d/'input').write_text(rows);(self.d/'candidate').write_text('{"path":"@@rs-0@@"}')
        return self.run_shell('native_resources_prepare "$D/input" "$D/candidate" "$D/manifest"')
    def test_checksum_pinned_download_and_cached_boot(self):
        r=self.prepare('0\tbinary\t'+self.url+'\n');self.assertEqual(r.returncode,0,r.stderr)
        manifest=(self.d/'manifest').read_text();sha=hashlib.sha256(self.server.payload).hexdigest();self.assertIn(sha,manifest)
        asset=self.ram/'ruleset'/('native-'+sha+'.srs');self.assertEqual(asset.read_bytes(),self.server.payload)
        self.assertIn(str(asset),(self.d/'candidate').read_text());self.server.calls.clear();self.server.payload=b'changed upstream'
        r=self.prepare(manifest);self.assertEqual(r.returncode,0,r.stderr);self.assertEqual(self.server.calls,[])
    def test_immutable_cache_reused_without_download_under_low_memory(self):
        payload=b'validated resource';sha=hashlib.sha256(payload).hexdigest()
        url='https://raw.githubusercontent.com/fixture/rules/'+('1'*40)+'/cn.srs'
        asset=self.ram/'ruleset'/('native-'+sha+'.srs');asset.write_bytes(payload)
        (self.c/'configs/native-resources.tsv').write_text('0\tbinary\t'+url+'\t'+sha+'\n')
        (self.root/'meminfo').write_text('MemAvailable: 13000 kB\n')
        result=self.prepare('0\tbinary\t'+url+'\n');self.assertEqual(result.returncode,0,result.stderr);self.assertEqual(self.server.calls,[])
        asset.write_bytes(b'changed');self.assertNotEqual(self.prepare('0\tbinary\t'+url+'\n').returncode,0)
        self.assertEqual(self.server.calls,[])

    def test_low_memory_keeps_validated_dataset_version_and_marks_staleness(self):
        payload=b'known version';sha=hashlib.sha256(payload).hexdigest()
        old='https://raw.githubusercontent.com/fixture/rules/'+('1'*40)+'/cn.srs'
        new='https://raw.githubusercontent.com/fixture/rules/'+('2'*40)+'/cn.srs'
        asset=self.ram/'ruleset'/('native-'+sha+'.srs');asset.write_bytes(payload)
        (self.c/'configs/native-resources.tsv').write_text('0\tbinary\t'+old+'\t'+sha+'\n');(self.root/'meminfo').write_text('MemAvailable: 12500 kB\n')
        result=self.prepare('0\tbinary\t'+new+'\n');self.assertEqual(result.returncode,0,result.stderr);self.assertTrue((self.d/'native-resource-retained').exists());self.assertIn(old,(self.d/'manifest').read_text());self.assertEqual(self.server.calls,[])
        self.assertNotEqual(self.prepare('0\tbinary\t'+new.replace('/cn.srs','/foreign.srs')+'\n').returncode,0)
        asset.write_bytes(b'corrupted');self.assertNotEqual(self.prepare('0\tbinary\t'+new+'\n').returncode,0)
        self.assertEqual(self.server.calls,[])

    def test_changed_source_cannot_replace_pinned_version(self):
        r=self.prepare('0\tbinary\t'+self.url+'\t'+('0'*64)+'\n');self.assertNotEqual(r.returncode,0)
        self.assertFalse((self.ram/'ruleset'/('native-'+('0'*64)+'.srs')).exists())
    def test_invalid_resource_input_is_rejected_before_network(self):
        for row in ['16\tbinary\t'+self.url,'0\tbad\t'+self.url,'0\tbinary\tfile:///etc/private','0\tbinary\t'+self.url+'\tbad']:
            self.assertNotEqual(self.prepare(row+'\n').returncode,0)
        self.assertEqual(self.server.calls,[])
    def test_memory_and_single_file_boundaries(self):
        (self.root/'meminfo').write_text('MemAvailable: 13000 kB\n');self.assertNotEqual(self.prepare('0\tbinary\t'+self.url+'\n').returncode,0);self.assertEqual(self.server.calls,[])
        (self.root/'meminfo').write_text('MemAvailable: 40960 kB\n');self.server.payload=b'x'*524289
        self.assertNotEqual(self.prepare('0\tbinary\t'+self.url+'\n').returncode,0)
    def test_aggregate_limit_and_unreferenced_cleanup(self):
        self.server.payload=b'x'*524288;r=self.prepare(''.join(str(i)+'\tbinary\t'+self.url+'\n'for i in range(5)));self.assertNotEqual(r.returncode,0)
        files=list((self.ram/'ruleset').glob('native-*'));self.assertEqual(len(files),1)
        self.assertEqual(self.run_shell('native_clean_cache').returncode,0);self.assertEqual(list((self.ram/'ruleset').glob('native-*')),[])
    def test_candidate_preserves_dns_and_imports_policy_before_template(self):
        base={'log':{},'dns':{'fixture':'local'},'inbounds':[{'tag':'local'}],'outbounds':[],'route':{},'experimental':{}}
        (self.c/'jsons/config.json').write_text('{\n'+',\n'.join(json.dumps(k)+':'+json.dumps(v,separators=(',',':'))for k,v in base.items())+'\n}\n')
        p={'outbounds':[{'type':'selector','tag':'proxy-main','outbounds':['node']},{'type':'direct','tag':'direct'},{'type':'anytls','tag':'node','server':'fixture.test'}],'route':{'rules':[{'domain_suffix':['google.com'],'outbound':'proxy-main'}]},'_panel_resources_b64':'','_panel_policy_b64':base64.b64encode(b'exact\ttest.example\tdirect\n').decode()}
        (self.d/'profile').write_text('{\n'+',\n'.join(json.dumps(k)+':'+json.dumps(v,separators=(',',':'))for k,v in p.items())+'\n}\n')
        r=self.run_shell('native_profile_candidate "$D/profile"');self.assertEqual(r.returncode,0,r.stderr);candidate=json.loads((self.d/'candidate.json').read_text())
        self.assertEqual(candidate['dns'],base['dns']);self.assertEqual(candidate['inbounds'],base['inbounds']);self.assertEqual(candidate['route']['rules'][0]['domain'],['test.example']);self.assertEqual(candidate['route']['rules'][1]['domain_suffix'],['google.com'])

if __name__=='__main__':unittest.main()
