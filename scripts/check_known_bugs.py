#!/usr/bin/env python3
"""
check_known_bugs.py - confirm the upstream bugs this skill documents are still in the installed source.

Each entry in known_bugs.json names a source file and a regex "signature" that matches the buggy code.
  PRESENT  the signature still matches: the skill's guidance stands.
  CHANGED  the file is there but the signature is gone: the bug may be fixed. Re-verify it, update the
           listed skill section and tracking issue, then delete the entry from known_bugs.json.
  MISSING  the source or file wasn't found, so nothing was checked.

Usage:
  python check_known_bugs.py [--mes PATH] [--wc PATH]
Exit code 1 when any bug is CHANGED.
"""
import argparse
import glob
import json
import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from query_mes_tags import detect_mes_path  # noqa: E402

WORKSHOP = r"C:\Program Files (x86)\Steam\steamapps\workshop\content\244850"


def detect_wc_path():
    """WeaponCore's CoreSystems scripts folder in the Steam workshop (the mod id varies between builds)."""
    hits = glob.glob(os.path.join(WORKSHOP, "*", "Data", "Scripts", "CoreSystems"))
    return max(hits, key=os.path.getmtime) if hits else None


def find_file(root, name):
    if not root:
        return None
    hits = glob.glob(os.path.join(root, "**", name), recursive=True)
    return hits[0] if hits else None


def issue_state(ref):
    """'OPEN'/'CLOSED' via the gh CLI, or '' when gh isn't available."""
    if not shutil.which("gh") or "#" not in ref:
        return ""
    repo, num = ref.split("#", 1)
    try:
        out = subprocess.run(["gh", "issue", "view", num, "-R", repo, "--json", "state", "--jq", ".state"],
                             capture_output=True, text=True, timeout=20)
        return out.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--mes", help="MES source root (default: auto-detect)")
    ap.add_argument("--wc", help="WeaponCore Data/Scripts/CoreSystems folder (default: newest in the Steam workshop)")
    a = ap.parse_args()

    roots = {"mes": a.mes or detect_mes_path(), "wc": a.wc or detect_wc_path()}
    bugs = json.load(open(os.path.join(HERE, "known_bugs.json"), encoding="utf-8"))["bugs"]
    changed = 0
    for b in bugs:
        path = find_file(roots.get(b["component"]), b["file"])
        state = issue_state(b.get("issue", ""))
        tracking = "%s%s" % (b.get("issue", ""), " (%s)" % state if state else "")
        if not path:
            print("MISSING  %-30s %s not found under %s" % (b["id"], b["file"], roots.get(b["component"])))
            continue
        text = open(path, encoding="utf-8-sig", errors="replace").read()
        if re.search(b["signature"], text):
            print("PRESENT  %-30s %s" % (b["id"], tracking))
        else:
            changed += 1
            print("CHANGED  %-30s signature gone from %s" % (b["id"], path))
            print("         %s" % b["summary"])
            print("         Re-verify, update %s and %s, then remove it from known_bugs.json." % (b["section"], tracking))
    return 1 if changed else 0


if __name__ == "__main__":
    sys.exit(main())
