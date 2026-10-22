"""Official LAN-chain generation and state preservation, using bounded tool stubs."""
from pathlib import Path
import json,os,subprocess,tempfile,unittest
ROOT=Path(__file__).resolve().parents[1]
class NativeAccess(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.p=Path(self.tmp.name);self.c=self.p/'C';self.w=self.p/'W';self.w.mkdir();self.bin=self.p/'bin';self.bin.mkdir()
  for directory in ['libs','configs','starts']:(self.c/directory).mkdir(parents=True)
  (self.c/'configs/ShellCrash.cfg').write_text('macfilter_type=白名单\nredir_mod=混合模式\ncommon_ports=OFF\ndns_nameserver=1.1.1.1\ndns_fallback=1.1.1.1\ndns_resolver=1.1.1.1\ndns_mod=mix\n')
  (self.c/'configs/command.env').write_text('')
  (self.c/'configs/mac').write_text('02:11:22:33:44:55\n');(self.c/'configs/ip_filter').write_text('192.168.1.25\n')
  for name in ['get_config.sh','check_cmd.sh']:(self.c/'libs'/name).write_bytes((ROOT/'vendor/ShellCrash-1.9.4/libs'/name).read_bytes())
  (self.c/'starts/fw_iptables.sh').write_bytes((ROOT/'vendor/ShellCrash-1.9.4/starts/fw_iptables.sh').read_bytes())
  (self.c/'starts/fw_getlanip.sh').write_text('getlanip(){ host_ipv4=192.168.1.0/24;reserve_ipv4=127.0.0.0/8; }\n')
  (self.c/'starts/panel_env.sh').write_text('PANEL_LAN_IP=192.168.1.1\n')
  for name,source in [('pidof','echo 1'),('iptables',r'''if [ "$1" = -h ];then exit 0;fi
if [ "$1" = -t ];then shift 2;fi
if [ "$1" = -S ];then
 case "$2" in shellcrash|shellcrash_dns|shellcrash_mark|shellcrash_out) echo "-N $2";echo "-A $2 -j RETURN";exit 0;;*)exit 1;;esac
fi
echo forbidden_direct_write >> "$NATIVE_LOG";exit 1'''),('iptables-restore','cat >> "$NATIVE_LOG";[ "${NATIVE_FAIL:-0}" = 0 ]')]:
   f=self.bin/name;f.write_text('#!/bin/sh\n'+source+'\n');f.chmod(0o700)
  source=(ROOT/'profiles/k2p/payload/starts/proxy-access-native.sh').read_text().replace('PATH=/usr/sbin:/usr/bin:/sbin:/bin;export PATH','PATH="'+str(self.bin)+':/usr/bin:/bin";export PATH').replace('/tmp/ShellCrash/traffic',str(self.p/'traffic'))
  self.script=self.p/'native.sh';self.script.write_text(source)
  self.env=dict(os.environ,CRASHDIR=str(self.c),NATIVE_LOG=str(self.p/'operations'),NATIVE_FAIL='0')
 def run_native(self,action,**extra):return subprocess.run(['sh',str(self.script),action,str(self.w)],env=dict(self.env,**extra),text=True,capture_output=True)
 def test_plan_uses_official_mac_and_ip_dns_tcp_udp_without_live_mutation(self):
  r=self.run_native('plan');self.assertEqual(r.returncode,0,r.stderr)
  rules=(self.w/'native-generated').read_text()
  self.assertIn('--mac-source 02:11:22:33:44:55',rules);self.assertIn('-s 192.168.1.25',rules)
  self.assertIn('REDIRECT --to-ports 7892',rules);self.assertIn('REDIRECT --to-ports 1053',rules);self.assertIn('MARK --set-mark 7892',rules)
  self.assertNotIn(':shellcrash_out',rules);self.assertFalse((self.p/'operations').exists())
 def test_empty_native_whitelist_never_falls_back_to_proxy_everyone(self):
  (self.c/'configs/mac').write_text('');(self.c/'configs/ip_filter').write_text('')
  self.assertEqual(self.run_native('plan').returncode,2);self.assertFalse((self.p/'operations').exists())
 def test_snapshot_does_not_change_manual_stop_routes_or_sets(self):
  r=self.run_native('snapshot');self.assertEqual(r.returncode,0,r.stderr)
  before=(self.w/'native-rules.before').read_text();self.assertIn(':shellcrash_out',before)
  self.assertFalse((self.p/'operations').exists())
 def test_restore_failure_is_reported_instead_of_success(self):
  self.assertEqual(self.run_native('snapshot').returncode,0)
  self.assertNotEqual(self.run_native('restore',NATIVE_FAIL='1').returncode,0)

 def test_existing_mode_function_keeps_its_non_errexit_contract(self):
  (self.c/'starts/cn_bypass.sh').write_text('cb_mode(){ echo rule; }\n')
  (self.c/'starts/traffic_mode.sh').write_text('traffic_mode_apply(){ missing=$(cat "$W/absent-mode" 2>/dev/null);printf "%s" "$1" > "$W/mode-called";return 0; }\n')
  self.assertEqual(self.run_native('snapshot').returncode,0)
  result=self.run_native('apply');self.assertEqual(result.returncode,0,result.stderr)
  self.assertEqual((self.w/'mode-called').read_text(),'rule')
