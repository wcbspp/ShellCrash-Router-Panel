#!/usr/bin/env python3
"""Run existing device suites against generated source, not duplicated UI copies."""
import argparse,subprocess,sys,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('profile',choices=['ax5','k2p','all']);a=p.parse_args()
for profile in ('ax5','k2p') if a.profile=='all' else [a.profile]:
 root=ROOT/'build'/profile
 subprocess.run([sys.executable,'-m','unittest','discover','-s','tests','-p','test_*.py'],cwd=root,check=True)
 scripts=sorted((root/'tests').glob('test_*.js'))
 for script in scripts:subprocess.run(['node',str(script)],cwd=root,check=True)
 print(profile+': Python suite and '+str(len(scripts))+' JS scripts passed',flush=True)
