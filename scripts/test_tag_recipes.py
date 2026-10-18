#!/usr/bin/env python3
"""
test_tag_recipes.py — Builds every recipe in references/tag_recipes.md into a throwaway mod
folder and runs the skill audits on it.

A ```mes block holds profiles: "== <SubtypeId>" starts one, its first line is the header, and
in a spawn group block the lines starting with "<" are its <Prefabs> body. A fenced block
whose info string is "xml <relative path>" is written to that path (dialogue bank files).

Usage:
  uv run scripts/test_tag_recipes.py
  uv run scripts/test_tag_recipes.py --keep    (print the folder and leave it in place)

Exit code: 0 = every audit passed with 0 errors, 1 = an audit reported errors.
"""

import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

SKILL_ROOT = Path(__file__).resolve().parent.parent
RECIPES = SKILL_ROOT / "references" / "tag_recipes.md"
FENCE = re.compile(r"^```(\S*)[ \t]*(.*?)\n(.*?)^```", re.S | re.M)


def profile_xml(subtype, lines):
    body = "\n".join("        " + line for line in lines)
    return (
        '    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">\n'
        f"      <Id>\n        <TypeId>Inventory</TypeId>\n        <SubtypeId>{subtype}</SubtypeId>\n      </Id>\n"
        f"      <Description>\n{body}\n      </Description>\n    </EntityComponent>\n"
    )


def spawn_group_xml(subtype, lines):
    tags = "\n".join("        " + line for line in lines if not line.startswith("<") and not line.startswith(" "))
    prefabs = "\n".join("        " + line for line in lines if line.startswith("<") or line.startswith(" "))
    return (
        f"    <SpawnGroup>\n      <Id>\n        <TypeId>SpawnGroupDefinition</TypeId>\n        <SubtypeId>{subtype}</SubtypeId>\n      </Id>\n"
        f"      <Description>\n{tags}\n      </Description>\n      <IsPirate>true</IsPirate>\n      <Frequency>1.0</Frequency>\n"
        f"      <Prefabs>\n{prefabs}\n      </Prefabs>\n    </SpawnGroup>\n"
    )


def build(out_dir):
    text = RECIPES.read_text(encoding="utf-8")
    recipe_count = 0
    for lang, info, body in FENCE.findall(text):
        if lang == "xml" and info:
            target = out_dir / info
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(body, encoding="utf-8")
            continue
        if lang != "mes":
            continue
        recipe_count += 1
        components, groups = [], []
        for chunk in re.split(r"^== ", body, flags=re.M)[1:]:
            subtype, _, rest = chunk.partition("\n")
            lines = [line.rstrip() for line in rest.splitlines() if line.strip()]
            if lines and lines[0] == "[Modular Encounters SpawnGroup]":
                groups.append(spawn_group_xml(subtype.strip(), lines))
            else:
                components.append(profile_xml(subtype.strip(), lines))
        sbc = ['<?xml version="1.0"?>\n<Definitions xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">\n']
        if groups:
            sbc += ["  <SpawnGroups>\n", *groups, "  </SpawnGroups>\n"]
        if components:
            sbc += ["  <EntityComponents>\n", *components, "  </EntityComponents>\n"]
        sbc.append("</Definitions>\n")
        (out_dir / f"Recipe{recipe_count:02d}.sbc").write_text("".join(sbc), encoding="utf-8")
    return recipe_count


def run(label, cmd):
    result = subprocess.run(cmd, cwd=SKILL_ROOT, capture_output=True, text=True)
    output = (result.stdout + result.stderr).strip()
    flagged = [line for line in output.splitlines() if line.startswith(("[ERROR]", "[WARN]", "[INFO]", "ERROR", "WARN"))]
    print(f"--- {label}: exit {result.returncode}")
    for line in flagged or output.splitlines()[-1:]:
        print("  " + line)
    return result.returncode == 0


def main():
    parser = argparse.ArgumentParser(description="Audit every recipe in references/tag_recipes.md.")
    parser.add_argument("--keep", action="store_true", help="leave the generated folder in place")
    args = parser.parse_args()

    out_dir = Path(tempfile.mkdtemp(prefix="mes-recipes-"))
    data_dir = out_dir / "Data"
    data_dir.mkdir()
    count = build(data_dir)
    print(f"Built {count} recipes into {data_dir}")

    ps = ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File"]
    ok = all([
        run("audit_sbc", ps + ["scripts/audit_sbc.ps1", "-Path", str(data_dir)]),
        run("audit_mes_tags", ps + ["scripts/audit_mes_tags.ps1", "-Path", str(data_dir)]),
        run("audit_mes_references", ps + ["scripts/audit_mes_references.ps1", "-Path", str(data_dir), "-SkipPrefabs"]),
        run("audit_unknown_tags", [sys.executable, "scripts/audit_unknown_tags.py", str(data_dir)]),
    ])

    if args.keep:
        print(f"Kept: {out_dir}")
    else:
        shutil.rmtree(out_dir, ignore_errors=True)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
