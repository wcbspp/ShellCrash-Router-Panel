"""Exercise startup/cleanup boundaries without changing the host or router."""
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class AuditRecovery(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)

    def shell(self, text, **env):
        return subprocess.run(["sh", "-c", text], env=dict(os.environ, **env),
                              capture_output=True, text=True, timeout=15)

    def test_fresh_ownerless_k2p_lock_is_busy_without_cleaning_job_files(self):
        source = (ROOT / "profiles/k2p/payload/starts/manage.sh").read_text()
        source = source[source.index("owner_live(){"):source.index("valid_id(){")]
        lock = self.root / "operation.lock"
        lock.mkdir()
        live_input = self.root / "native-policy.input"
        live_input.write_text("still being prepared")
        script = 'stat(){ echo "$LOCK_TIME"; }; date(){ echo 1000; }; act=restorego\n'
        r = self.shell(script + source + "\nlock\n", D=str(self.root), LOCK_TIME="999")
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual(live_input.read_text(), "still being prepared")
        self.assertTrue(lock.exists())
        self.assertFalse((self.root / "operation.lock.reap").exists())

    def test_ax5_failed_second_move_removes_only_the_new_tool_directory(self):
        source = (ROOT / "profiles/ax5/install.sh").read_text()
        cleanup = source[source.index("cleanup(){"):source.index("trap cleanup EXIT")]
        start = source.index(' mv "$stage/tool" "$T"')
        publish = source[start:source.index("\nelse", start)]
        stage = self.root / "stage"
        (stage / "tool").mkdir(parents=True)
        (stage / "panel").mkdir()
        runtime = self.root / "ram"
        runtime.mkdir()
        (runtime / "operation.lock").mkdir()
        cleanup = cleanup.replace("/tmp/ShellCrash", str(runtime))
        script = """set -e
mode=--install;tool_moved=0;panel_moved=0;service_setup=0;rollback=;pending=;checkstage=
mv(){ case "$2" in "$C") return 1;; esac; command mv "$@"; }
"""
        r = self.shell(script + cleanup + "\ntrap cleanup EXIT\n" + publish,
                       stage=str(stage), T=str(self.root / "tool"), C=str(self.root / "panel"))
        self.assertNotEqual(r.returncode, 0)
        self.assertFalse((self.root / "tool").exists())
        self.assertFalse((runtime / "operation.lock").exists())

    def test_completed_restore_prunes_payload_but_failed_rollback_keeps_it(self):
        paths = ("profiles/ax5/ax5/restore-worker.sh", "profiles/k2p/payload/starts/restore-worker.sh")
        for i, path in enumerate(paths):
            source = (ROOT / path).read_text()
            start = source.index("finish(){")
            finish = source[start:source.index("\nif [ \"${SC_RESTORE_HANDOFF", start)]
            for succeeded in (True, False):
                with self.subTest(path=path, succeeded=succeeded):
                    target = self.root / f"{i}-{succeeded}"
                    target.mkdir()
                    payload = target / "rollback-application.tar.gz"
                    payload.touch()
                    (target / "credentials").mkdir()
                    r = self.shell("field(){ echo fixture; }; phase(){ :; }; rollback(){ return 1; };\n"
                                   + finish + "\nfinish\n", X=str(target), D=str(self.root), R=str(self.root),
                                   ID="12345678", STATE="done", FINISHED=str(int(succeeded)), STOPPED="1")
                    self.assertEqual(r.returncode, 0, r.stderr)
                    self.assertEqual(payload.exists(), not succeeded)
                    self.assertEqual((target / "credentials").exists(), not succeeded)
                    self.assertIn("done" if succeeded else "rollback_failed", (target / "result.json").read_text())
