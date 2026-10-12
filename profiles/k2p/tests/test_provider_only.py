from pathlib import Path
import os,subprocess,tempfile,unittest
ROOT=Path(__file__).resolve().parents[1]
class ProviderOnly(unittest.TestCase):
 def test_conversion_is_absent_in_ui_and_blocked_before_network(self):
  html=(ROOT/'payload/ui/index.html').read_text();self.assertNotIn('<option value="convert">',html)
  with tempfile.TemporaryDirectory()as tmp:
   p=Path(tmp);c=p/'persist';d=p/'ram';(c/'starts').mkdir(parents=True);d.mkdir();(c/'starts/panel_env.sh').write_text(':\n');(c/'config').write_text('existing')
   source=(ROOT/'payload/starts/manage.sh').read_text().replace('/etc/storage/ShellCrash',str(c)).replace('/tmp/sc-admin',str(d));script=p/'manage.sh';script.write_text(source)
   (p/'bin').mkdir();curl=p/'bin/curl';curl.write_text('#!/bin/sh\ntouch "'+str(p/'network')+'"\nexit 1\n');curl.chmod(0o700)
   result=subprocess.run(['sh',str(script),'fetchconvert','1234abcd'],env=dict(os.environ,PATH=str(p/'bin')+':'+os.environ['PATH']),capture_output=True)
   self.assertNotEqual(result.returncode,0);self.assertFalse((p/'network').exists());self.assertEqual((c/'config').read_text(),'existing');self.assertIn('未发送',(d/'message').read_text())
