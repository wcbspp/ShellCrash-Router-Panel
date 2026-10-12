from pathlib import Path
import subprocess,tempfile,unittest
ROOT=Path(__file__).resolve().parents[1]
class UploadHotpath(unittest.TestCase):
 def test_chunks_skip_configuration_and_validate_identity_phase_size(self):
  with tempfile.TemporaryDirectory()as tmp:
   d=Path(tmp);script=d/'put.sh'
   source=(ROOT/'payload/starts/manage.sh').read_text().replace('D=/tmp/sc-admin','D='+str(d))
   source=source.replace('. "$PANEL_HOME/starts/panel_env.sh" || exit 1','exit 99 # must never reach configuration during put')
   script.write_text(source);(d/'id').write_text('1234abcd\n');(d/'phase').write_text('uploading\n');(d/'upload.parts').write_text('')
   def put(identity,chunk):return subprocess.run(['sh',str(script),'put',identity,chunk],capture_output=True)
   self.assertEqual(put('1234abcd','0000QUJDRA==').returncode,0)
   self.assertEqual((d/'upload.parts').read_text(),'0000 QUJDRA==\n')
   for identity,chunk in [('bad','0000QQ=='),('0000abcd','0000QQ=='),('1234abcd','zzzzQQ=='),('1234abcd','0000;id'),('1234abcd','0000'+'Q'*17)]:self.assertNotEqual(put(identity,chunk).returncode,0)
   (d/'phase').write_text('done\n');self.assertNotEqual(put('1234abcd','0001QQ==').returncode,0)
   (d/'phase').write_text('uploading\n');(d/'upload.parts').write_bytes(b'x'*400000);self.assertNotEqual(put('1234abcd','0001QQ==').returncode,0)
