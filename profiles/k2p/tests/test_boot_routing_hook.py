"""Exercise the boot hook with a sparse firmware environment and an early status read."""
import os, subprocess, tempfile, unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

class BootRoutingHook(unittest.TestCase):
 def test_hook_initializes_runtime_and_router_address(self):
  with tempfile.TemporaryDirectory() as tmp:
   p=Path(tmp);c=p/'config';d=p/'runtime';s=c/'starts';s.mkdir(parents=True);(c/'configs').mkdir();(p/'ram').mkdir();b=p/'bin';b.mkdir()
   for name in ['iptables','ip6tables']:
    f=b/name;f.write_text('#!/bin/sh\n[ "$1" != -D ] || exit 1\necho MARK\n');f.chmod(0o700)
   (c/'configs/ShellCrash.cfg').write_text('redir_mod=混合模式\n')
   (s/'panel_env.sh').write_text('PANEL_LAN_IP=192.168.123.1\n')
   (s/'proxy-access.sh').write_text((ROOT/'payload/starts/proxy-access.sh').read_text())
   (s/'subscription-quota.sh').write_text('exit 0\n')
   (s/'policy_capture.sh').write_text('policy_capture_apply(){ [ -d "$D" ] && [ "$PANEL_LAN_IP" = 192.168.123.1 ] && echo ready > "$D/result"; }\n')
   hook=(ROOT/'payload/starts/panel_afstart.sh').read_text().replace('/etc/storage/ShellCrash',str(c)).replace('/tmp/sc-admin',str(d)).replace('/tmp/ShellCrash',str(p/'ram'))
   # Only firmware commands are mocked; the environment initialization is real.
   script='pidof(){ :; };ip(){ :; };iptables(){ if [ "$1" = -D ];then return 1;fi;echo MARK; };logger(){ echo "$*" >&2; };\n'+hook
   r=subprocess.run(['sh','-c',script],env={'PATH':str(b)+':/bin:/usr/bin','SC_ACCESS_RUNTIME':str(p/'acl')},capture_output=True,text=True)
   self.assertEqual(r.returncode,0,r.stderr);self.assertEqual((d/'result').read_text().strip(),'ready')

 def refresh(self,applied,checked='rule:ready',busy=False):
  with tempfile.TemporaryDirectory() as tmp:
   p=Path(tmp);(p/'cn-applied').write_text(applied);(p/'cn-checked').write_text(checked)
   if busy:(p/'operation.lock').mkdir()
   # Execute the actual refresh function, without loading unrelated firmware helpers.
   text=(ROOT/'payload/starts/cn_bypass.sh').read_text();fn=text[text.index('cb_refresh(){'):text.index('\ncb_save(){')]
   script='D="$1";cb_enabled(){ return 0; };cb_mode(){ echo rule; };cb_safe(){ echo ready; };cb_rules(){ echo "$1"; };\n'+fn+'\ncb_refresh'
   r=subprocess.run(['sh','-c',script,'fixture',str(p)],capture_output=True,text=True)
   return r.stdout.strip()
 def test_chain_not_ready_is_retried_after_boot(self):self.assertEqual(self.refresh('rule:stopped'),'rule')
 def test_active_state_does_not_reapply_each_poll(self):self.assertEqual(self.refresh('rule:ready'),'')
 def test_existing_operation_keeps_refresh_read_only(self):self.assertEqual(self.refresh('rule:stopped',busy=True),'')

if __name__=='__main__':unittest.main()
