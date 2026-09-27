#!/usr/bin/env python3
"""
audit_unknown_tags.py - find tags that MES will silently ignore.

MES parses each profile type (`[RivalAI Autopilot]`, `[RivalAI Trigger]`, ...) with a fixed list of
`tag.Contains("[TagName:")` checks. A tag that is not in that list for its profile type is not an error:
MES just never reads it, and the field keeps its default. This script compares every `[Tag:value]` line
inside each profile against `scripts/mes_tag_cache.json` (built from the MES source by
`query_mes_tags.py --rebuild-cache`) and reports tags the profile type does not parse.

Typical hits: a tag copied from an older wiki page or another profile type (`[StrikeBeginPlanetAttackRunDistance]`
in an autopilot profile), a tag that exists as a field but has no parser (`[AttackRunMaxTimeTrigger]`), or a typo.

Every profile type in the cache is checked. `[MES AI X]` headers are checked as `[RivalAI X]`, and the three
`[MES Event ... Template]` headers as their non-template profile. Use --profile to check only some types.
A hit on a tag parsed by unusual custom code is still worth confirming in the source before deleting it.

It also checks each known tag's value against the TagParse function that reads it (recorded in the cache as
`parser`). Those parsers fail silently: an unparseable value leaves the field at its default, with no log.
The classic trap is a Yes/No/Ignore tag (`[GridDestructible:]`, `[GridEditable:]`, `[IsStatic:]` ...) given
`true`/`false`: MES's CheckEnum parse is case-sensitive and only knows Yes/No/Ignore, so the action does
nothing. Values containing a `{token}` are skipped (they are only known after substitution).

Usage:
  python audit_unknown_tags.py <folder-or-file.sbc> [more paths ...]
  python audit_unknown_tags.py path --profile "RivalAI Trigger"       (check only this type; repeatable)
  python audit_unknown_tags.py path --show-ok                         (also list files with no findings)
  (--all is accepted for compatibility; every type is checked by default.)

Exit code: 0 = nothing found, 1 = unknown tags or invalid values found, 2 = usage / cache error.
Only profiles whose `<Description>` starts with a recognised `[Profile Type]` header are checked.
Markdown files are scanned too: the fenced code blocks of the skill's own references/*.md.
"""
import argparse
import difflib
import json
import os
import re
import sys
import xml.etree.ElementTree as ET
from collections import defaultdict

INT_RE = re.compile(r"^\s*[+-]?\d+\s*$")
NUM_RE = re.compile(r"^\s*[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?\s*$")
# TagParse.cs parser -> (value accepted?, what MES accepts, what happens otherwise). Each rule mirrors the
# parser's own TryParse call: bool.TryParse (case-insensitive), CheckEnum Enum.TryParse (case-SENSITIVE,
# members Ignore/No/Yes or their numbers), BoolEnum Enum.TryParse(ignoreCase: true), int/long/double/float
# TryParse, and TagIntOrDayCheck's literal "Day".
VALUE_RULES = {
    "TagBoolCheck": (lambda v: v.strip().lower() in ("true", "false"),
                     "true or false", "ignored, field keeps its default"),
    "TagCheckEnumCheck": (lambda v: v.strip() in ("Yes", "No", "Ignore") or INT_RE.match(v),
                          "Yes, No or Ignore (case-sensitive)", "ignored, field stays Ignore so the setting has no effect"),
    "TagBoolEnumCheck": (lambda v: v.strip().lower() in ("true", "false", "none"),
                         "True, False or None", "field is reset to None"),
    "TagIntCheck": (lambda v: INT_RE.match(v), "a whole number", "ignored, field keeps its default"),
    "TagLongCheck": (lambda v: INT_RE.match(v), "a whole number", "ignored, field keeps its default"),
    "TagDoubleCheck": (lambda v: NUM_RE.match(v), "a number", "ignored, field keeps its default"),
    "TagFloatCheck": (lambda v: NUM_RE.match(v), "a number", "ignored, field keeps its default"),
    "TagIntOrDayCheck": (lambda v: v.strip() == "Day" or INT_RE.match(v),
                         "a whole number or Day", "ignored, field keeps its default"),
    # ModifierEnum (Enums.cs): no Increase/Decrease members, and the list overload drops a failed
    # entry, which silently skips its index-aligned zone/counter change.
    "TagModifierEnumCheck": (lambda v: v.strip() in ("None", "Set", "Add", "Subtract", "Multiply", "Divide")
                             or INT_RE.match(v),
                             "Set, Add, Subtract, Multiply or Divide (case-sensitive)",
                             "ignored, the change is skipped"),
}
# Headers that MES parses with another profile's tag list.
HEADER_ALIASES = {
    "RivalAI Behaviour": "RivalAI Behavior",
    "MES Event Template": "MES Event",
    "MES Event Action Template": "MES Event Action",
    "MES Event Condition Template": "MES Event Condition",
}
# Every [Header] MES registers a profile under (ProfileManager.cs / SpawnGroupManager.cs), after
# normalize_header(). A Description whose header is not listed is never loaded by MES at all.
KNOWN_HEADERS = {
    "Modular Encounters SpawnGroup", "Modular Encounters Territory",
    "RivalAI Action", "RivalAI Autopilot", "RivalAI Behavior", "RivalAI Chat", "RivalAI Command",
    "RivalAI Condition", "RivalAI Spawn", "RivalAI Target", "RivalAI Trigger", "RivalAI TriggerGroup",
    "RivalAI Waypoint", "RivalAI Weapons",
    "MES Block Replacement", "MES Bot Spawn", "MES Contract Block", "MES Dereliction", "MES Event",
    "MES Event Action", "MES Event Condition", "MES Event TemplateGroup", "MES Faction Icon", "MES Loot",
    "MES Loot Group", "MES Manipulation", "MES Manipulation Group", "MES Mission", "MES Player Condition",
    "MES Prefab Data", "MES Prefab Gravity", "MES Replenishment", "MES SafeZone", "MES Shipyard",
    "MES Spawn Conditions", "MES Spawn Conditions Group", "MES Static Encounter", "MES Store",
    "MES Suit Upgrades", "MES Weapon Mod Rules", "MES Zone", "MES Zone Conditions",
}
TRIGGER_TYPES = set()
PARSERS = {}
CACHE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mes_tag_cache.json")
TAG_RE = re.compile(r"\[([A-Za-z0-9_]+):([^\]]*)\]")
HEADER_RE = re.compile(r"^\s*\[([A-Za-z][A-Za-z0-9 ]*)\]", re.M)


def load_cache():
    with open(CACHE, encoding="utf-8") as f:
        data = json.load(f)
    valid = defaultdict(set)
    parsers = {}
    for t in data["tags"]:
        valid[t["profile"]].add(t["tag"])
        if t.get("parser"):
            parsers[(t["profile"], t["tag"])] = t["parser"]
    global TRIGGER_TYPES, PARSERS
    TRIGGER_TYPES = set(data.get("values", {}).get("RivalAI Trigger.Type", []))
    # A SpawnGroup's own Description is also parsed as its first Spawn Conditions and Manipulation profile.
    valid["Modular Encounters SpawnGroup"] |= valid["MES Spawn Conditions"] | valid["MES Manipulation"]
    for src in ("MES Manipulation", "MES Spawn Conditions", "Modular Encounters SpawnGroup"):
        for (p, tag), fn in list(parsers.items()):
            if p == src:
                parsers.setdefault(("Modular Encounters SpawnGroup", tag), fn)
    PARSERS = parsers
    return valid


def normalize_header(header):
    if header.startswith("MES AI "):
        header = "RivalAI " + header[len("MES AI "):]
    return HEADER_ALIASES.get(header, header)


def profiles_in(path):
    """Yield (subtype_id, header, description) for every profile in an .sbc file or .md code block."""
    if path.lower().endswith(".md"):
        yield from md_profiles_in(path)
        return
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError as e:
        print("  [skip] %s: XML parse error: %s" % (path, e))
        return
    comps = list(root.iter("EntityComponent")) + list(root.iter("SpawnGroup"))
    for comp in comps:
        sid = comp.findtext("Id/SubtypeId") or "?"
        desc = comp.findtext("Description") or ""
        m = HEADER_RE.search(desc)
        if m:
            yield sid, normalize_header(m.group(1).strip()), desc


def md_profiles_in(path):
    """Profiles inside fenced code blocks of a Markdown reference: each <Description> body, or a bare
    block of tag lines that starts with a [Profile Type] header. Prose outside code blocks is skipped,
    so a sentence warning that a tag does not exist is not reported."""
    text = open(path, encoding="utf-8").read()
    for fence in re.finditer(r"^```[^\n]*\n(.*?)^```", text, re.M | re.S):
        body = fence.group(1)
        line = text.count("\n", 0, fence.start()) + 1
        descs = re.findall(r"<Description>(.*?)</Description>", body, re.S) or [body]
        for desc in descs:
            m = HEADER_RE.search(desc)
            if m:
                yield "line %d" % line, normalize_header(m.group(1).strip()), desc


def files_under(paths):
    for p in paths:
        if os.path.isfile(p):
            yield p
        else:
            for dp, _, fns in os.walk(p):
                for fn in fns:
                    if fn.lower().endswith((".sbc", ".md")):
                        yield os.path.join(dp, fn)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("paths", nargs="+")
    ap.add_argument("--profile", action="append", help="check only this profile type (repeatable)")
    ap.add_argument("--all", action="store_true", help="accepted for compatibility; every type is checked by default")
    ap.add_argument("--show-ok", action="store_true")
    a = ap.parse_args()
    try:
        valid = load_cache()
    except (OSError, ValueError, KeyError) as e:
        print("cannot read %s: %s" % (CACHE, e))
        return 2
    wanted = set(a.profile) if a.profile else set(valid)
    total = 0
    bad_values = 0
    for f in files_under(a.paths):
        hits = []
        checked = 0
        for sid, header, desc in profiles_in(f):
            if header not in KNOWN_HEADERS:
                hits.append("  %s [%s] unrecognized profile header - MES never loads this profile" % (sid, header))
                continue
            if header not in valid or header not in wanted:
                continue
            checked += 1
            for m in TAG_RE.finditer(desc):
                tag = m.group(1)
                if header == "RivalAI Trigger" and tag == "Type" and TRIGGER_TYPES:
                    value = m.group(2).strip()
                    # "Manual" is a convention, not a check: no per-tick check matches it, so the trigger
                    # only ever fires through [ManuallyActivatedTriggerNames/Tags:], which is the intent.
                    if value not in TRIGGER_TYPES and value != "Manual":
                        guess = difflib.get_close_matches(value, TRIGGER_TYPES, n=1, cutoff=0.6)
                        hits.append("  %s [%s] [Type:%s] is not a trigger type MES checks for%s" % (
                            sid, header, value, " (did you mean %s?)" % guess[0] if guess else ""))
                    continue
                if tag not in valid[header]:
                    guess = difflib.get_close_matches(tag, valid[header], n=1, cutoff=0.8)
                    other = sorted(p for p, tags in valid.items() if tag in tags and p != header)
                    note = ""
                    if guess:
                        note = " (did you mean %s?)" % guess[0]
                    elif other:
                        note = " (is a %s tag)" % ", ".join(other)
                    hits.append("  %s [%s] [%s:...]%s" % (sid, header, tag, note))
                    continue
                rule = VALUE_RULES.get(PARSERS.get((header, tag)))
                value = m.group(2)
                if rule and "{" not in value and not rule[0](value):
                    hits.append("  %s [%s] [%s:%s] invalid value - MES accepts %s; otherwise %s" % (
                        sid, header, tag, value, rule[1], rule[2]))
                    bad_values += 1
        if hits:
            print("%s" % f)
            print("\n".join(hits))
            total += len(hits)
        elif a.show_ok and checked:
            print("%s: OK (%d profiles)" % (f, checked))
    print("\n%d unknown tag(s) and %d invalid value(s) found." % (total - bad_values, bad_values))
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
