import json,subprocess,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class Groups(unittest.TestCase):
 def test_stable_targets_and_existing_rules(self):
  with tempfile.TemporaryDirectory() as td:
   p=Path(td);cfg={'outbounds':[{'type':'selector','tag':'proxy-main','outbounds':['node']},{'type':'direct','tag':'direct'},{'type':'trojan','tag':'node','server':'example.com','server_port':443,'password':'fixture'}],'route':{'rules':[{'action':'hijack-dns'},{'ip_cidr':['10.0.0.0/8'],'outbound':'direct'}],'final':'proxy-main'}}
   (p/'cfg').write_text('{\n'+',\n'.join(json.dumps(k)+':'+json.dumps(v,ensure_ascii=False,separators=(',',':')) for k,v in cfg.items())+'\n}\n');(p/'old').write_text('');(p/'input').write_text(''.join('suffix\t'+d+'\tnode\n' for d in ['google.com','gstatic.com','googleapis.com']))
   def run(config,old):return subprocess.run(['awk','-v','input='+str(p/'input'),'-v','oldfile='+str(old),'-v','compiled='+str(p/'rules'),'-v','metadata='+str(p/'meta'),'-f',str(ROOT/'payload/starts/policy_merge.awk'),str(config)],capture_output=True,text=True)
   r=run(p/'cfg',p/'old');self.assertEqual(r.returncode,0,r.stderr);out=json.loads(r.stdout);g=next(o for o in out['outbounds'] if o['tag']=='分流/谷歌');self.assertEqual(g['default'],'node');self.assertNotIn('分流/谷歌',g['outbounds']);self.assertEqual(out['route']['rules'][1]['outbound'],'分流/谷歌');self.assertEqual(out['route']['rules'][-1],cfg['route']['rules'][-1]);self.assertIn('\t分流/谷歌', (p/'meta').read_text())
   (p/'cfg2').write_text(r.stdout);(p/'input').write_text((p/'meta').read_text());(p/'old2').write_text((p/'rules').read_text());r2=run(p/'cfg2',p/'old2');self.assertEqual(r2.returncode,0,r2.stderr);self.assertEqual(json.loads(r2.stdout),out)
if __name__=='__main__':unittest.main()
