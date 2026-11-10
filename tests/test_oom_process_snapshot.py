import unittest,subprocess,tempfile,shlex
from pathlib import Path
SOURCE=Path(__file__).resolve().parents[1]/'shared/lib/oom-monitor.sh'
class ProcessSnapshot(unittest.TestCase):
 def test_rss_order_and_kernel_thread_without_swap(self):
  line=next(x.strip() for x in SOURCE.read_text().splitlines() if x.lstrip().startswith("awk 'function emit"))
  with tempfile.TemporaryDirectory()as d:
   paths=[]
   for i,(name,rss)in enumerate([('kernel',None),('CrashCore',40000),('zerotier',8000)]):
    p=Path(d)/str(i);p.write_text('Name:\t'+name+'\nPid:\t'+str(i+1)+'\n'+('VmRSS:\t'+str(rss)+' kB\n' if rss else ''));paths.append(shlex.quote(str(p)))
   cmd=line.replace('/proc/[0-9]*/status',' '.join(paths))
   result=subprocess.run(['sh','-c',cmd],capture_output=True,text=True,check=True)
   rows=[r.split() for r in result.stdout.splitlines()]
   self.assertEqual([r[0]for r in rows],['CrashCore','zerotier','kernel'])
   self.assertEqual(rows[0][2:],["40000","0"])
