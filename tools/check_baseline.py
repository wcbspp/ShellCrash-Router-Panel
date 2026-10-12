#!/usr/bin/env python3
"""Prove profile compilation preserves the pre-migration source bytes."""
import hashlib,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def check(profile):
 expected=json.loads((ROOT/'profiles'/profile/'baseline.sha256.json').read_text());changes=json.loads((ROOT/'profiles'/profile/'intentional_changes.json').read_text()) if (ROOT/'profiles'/profile/'intentional_changes.json').exists() else {}
 for name,sha in expected.items():
  if changes.get(name,{}).get('removed'):
   if (ROOT/'build'/profile/name).exists():raise SystemExit(f'{profile}/{name}: obsolete file remains')
   continue
  actual=hashlib.sha256((ROOT/'build'/profile/name).read_bytes()).hexdigest()
  if name in changes:
   if actual!=changes[name]['sha256']:raise SystemExit(f'{profile}/{name}: unreviewed deployment change')
  elif actual!=sha:raise SystemExit(f'{profile}/{name}: unexpected change')
 print(f'{profile}: {len(expected)-len(changes)} unchanged files; {len(changes)} reviewed deployment changes')
if __name__=='__main__':
 for profile in ('ax5','k2p'):check(profile)
