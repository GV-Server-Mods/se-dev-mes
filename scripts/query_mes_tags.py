#!/usr/bin/env python3
"""
query_mes_tags.py — High-Performance Tag and Profile Query CLI for MES & RivalAI.
Searches the local MES source code or offline tag cache (mes_tag_cache.json) to display
valid tags, profile types, expected data types, and source locations.

Usage:
  python query_mes_tags.py --tag "ChangeZone"
  python query_mes_tags.py --profile "Autopilot"
  python query_mes_tags.py --tag "Counters" --profile "Event"
  python query_mes_tags.py --rebuild-cache
"""

import os
import sys
import re
import json
import hashlib
import argparse
import subprocess
from datetime import datetime, timezone

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CACHE_FILE = os.path.join(SCRIPT_DIR, "mes_tag_cache.json")

def get_candidate_paths():
    candidates = []

    # 1. Environment-derived AppData / Roaming paths
    appdata = os.environ.get('APPDATA') or os.path.expandvars(r'%AppData%')
    if appdata and os.path.isdir(appdata):
        candidates.append(os.path.join(appdata, 'SpaceEngineers', 'Mods', 'Modular-Encounters-Systems', 'Data', 'Scripts', 'ModularEncountersSystems'))
        candidates.append(os.path.join(appdata, 'SpaceEngineers', 'Mods', 'Modular-Encounters-Systems'))

    userprofile = os.environ.get('USERPROFILE') or os.path.expanduser('~')
    if userprofile and os.path.isdir(userprofile):
        candidates.append(os.path.join(userprofile, 'AppData', 'Roaming', 'SpaceEngineers', 'Mods', 'Modular-Encounters-Systems', 'Data', 'Scripts', 'ModularEncountersSystems'))
        candidates.append(os.path.join(userprofile, 'AppData', 'Roaming', 'SpaceEngineers', 'Mods', 'Modular-Encounters-Systems'))
        candidates.append(os.path.join(userprofile, 'source', 'repos', 'Modular-Encounters-Systems'))
        candidates.append(os.path.join(userprofile, 'source', 'repos', 'MES'))

    # 2. Multi-drive Steam Workshop paths (Space Engineers appid 244850, MES item 1521905890)
    for d in ['C', 'D', 'E', 'F', 'G', 'H', 'Z']:
        drive_root = f"{d}:\\"
        if not os.path.exists(drive_root):
            continue
        steam_bases = [
            os.path.join(drive_root, 'Program Files (x86)', 'Steam'),
            os.path.join(drive_root, 'Program Files', 'Steam'),
            os.path.join(drive_root, 'Steam'),
            os.path.join(drive_root, 'SteamLibrary'),
        ]
        for sb in steam_bases:
            ws_item = os.path.join(sb, 'steamapps', 'workshop', 'content', '244850', '1521905890')
            candidates.append(os.path.join(ws_item, 'Data', 'Scripts', 'ModularEncountersSystems'))
            candidates.append(ws_item)

    return candidates

def resolve_mes_path(path):
    if not path or not os.path.isdir(path):
        return None
    scripts_sub = os.path.join(path, 'Data', 'Scripts', 'ModularEncountersSystems')
    if os.path.isdir(scripts_sub):
        return scripts_sub
    return path

def detect_mes_path():
    for path in get_candidate_paths():
        resolved = resolve_mes_path(path)
        if resolved and os.path.isdir(resolved):
            return resolved
    return None

PROFILE_FILES = {
    'RivalAI Action': ['ActionReferenceProfile.cs', 'ActionProfile.cs'],
    'RivalAI Condition': ['ConditionReferenceProfile.cs', 'ConditionProfile.cs'],
    'RivalAI Trigger': ['TriggerProfile.cs'],
    'RivalAI TriggerGroup': ['TriggerGroupProfile.cs'],
    'RivalAI Autopilot': ['AutoPilotProfile.cs'],
    'RivalAI Target': ['TargetProfile.cs'],
    'RivalAI Chat': ['ChatProfile.cs'],
    'RivalAI Spawn': ['SpawnProfile.cs'],
    'RivalAI Command': ['CommandProfile.cs'],
    'RivalAI Waypoint': ['WaypointProfile.cs'],
    'RivalAI Weapons': ['WeaponSystemReference.cs'],
    # Behavior-level tags are parsed by the behavior subclass and each subsystem, not one profile class.
    'RivalAI Behavior': ['BehaviorManager.cs', 'CoreBehavior.cs','CargoShip.cs', 'Escort.cs', 'Fighter.cs', 'FighterPlane.cs',
                         'HorseFighter.cs', 'Horsefly.cs', 'HorseNautical.cs', 'Hunter.cs', 'Nautical.cs',
                         'NauticalRoutes.cs', 'Passive.cs', 'Scout.cs', 'Sniper.cs', 'Strike.cs',
                         'AutoPilotSystem.cs', 'DamageSystem.cs', 'DespawnSystem.cs', 'EscortSystem.cs',
                         'TargetingSystem.cs', 'TriggerSystem.cs', 'WeaponSystem.cs'],
    'MES Event Action': ['EventActionReference.cs', 'EventActionProfile.cs'],
    'MES Event Condition': ['EventConditions.cs', 'EventCondition.cs'],
    'MES Event': ['EventProfile.cs'],
    'MES Event TemplateGroup': ['TemplateEventGroup.cs'],
    'MES Spawn Conditions': ['SpawnConditionsProfile.cs'],
    'MES Spawn Conditions Group': ['SpawnConditionsGroup.cs'],
    'MES Manipulation': ['ManipulationProfile.cs'],
    'MES Manipulation Group': ['ManipulationGroup.cs'],
    'MES Loot Group': ['LootGroup.cs'],
    'Modular Encounters SpawnGroup': ['ImprovedSpawnGroup.cs'],
    'MES Block Replacement': ['BlockReplacementProfile.cs'],
    'MES Dereliction': ['DerelictionProfile.cs'],
    'MES Faction Icon': ['FactionIconProfile.cs'],
    'MES Bot Spawn': ['BotSpawnProfile.cs'],
    'MES Replenishment': ['ReplenishmentProfile.cs'],
    'MES Loot': ['LootProfile.cs'],
    'MES Store': ['StoreProfile.cs'],
    'MES Shipyard': ['ShipyardProfile.cs'],
    'MES Static Encounter': ['StaticEncounter.cs'],
    'MES SafeZone': ['SafeZoneProfile.cs'],
    'MES Zone': ['Zone.cs'],
    'MES Zone Conditions': ['ZoneConditionsProfile.cs'],
    'MES Player Condition': ['PlayerConditionProfile.cs', 'PlayerCondition.cs'],
    'MES Weapon Mod Rules': ['WeaponModRulesProfile.cs'],
    'MES Mission': ['MissionProfile.cs'],
    'MES Contract Block': ['ContractBlockProfile.cs'],
    'MES Suit Upgrades': ['SuitUpgradesProfile.cs'],
    'MES Prefab Data': ['PrefabDataProfile.cs'],
    'MES Prefab Gravity': ['PrefabGravityProfile.cs'],
}

TYPE_MAP = {
    'TagBoolCheck': 'bool (true/false)',
    'TagStringCheck': 'string',
    'TagStringListCheck': 'List<string> (comma-separated)',
    'TagIntCheck': 'int',
    'TagIntListCheck': 'List<int> (comma-separated)',
    'TagDoubleCheck': 'double',
    'TagDoubleListCheck': 'List<double> (comma-separated)',
    'TagFloatCheck': 'float',
    'TagVector3DCheck': 'Vector3D ({X:0 Y:0 Z:0})',
    'TagVector3DListCheck': 'List<Vector3D>',
    'TagDirectionEnumCheck': 'Direction enum',
    'TagModifierEnumCheck': 'ModifierEnum (None, Add, Multiply, ...)',
    'TagCompareEnumCheck': 'CounterCompareEnum (GreaterOrEqual, Less, Equal, ...)',
    'TagDateTimeCheck': 'DateTime / TimeSpan (ms or ISO)',
    'CustomTagParse': 'custom / block parse',
}

def find_mes_files(mes_path):
    file_map = {}
    for root, _, files in os.walk(mes_path):
        for f in files:
            f_lower = f.lower()
            for ptype, target_files in PROFILE_FILES.items():
                for target in target_files:
                    if f_lower == target.lower():
                        if ptype not in file_map:
                            file_map[ptype] = []
                        file_map[ptype].append(os.path.join(root, f))
    return file_map

BLOCK_TAG_RE = re.compile(r'\.(?:StartsWith|Contains)\("\[?[a-zA-Z0-9_]+[:"]')
TAGPARSE_RE = re.compile(r'TagParse\.(\w+)\(')


def block_parser(lines, idx):
    """TagParse function used by the `if (tag.Contains("[X:"))` block that starts on line idx (1-based):
    the first TagParse.* call before the next tag test, within a few lines. None if the block parses
    the value some other way."""
    for j in range(idx - 1, min(idx + 11, len(lines))):
        if j > idx - 1 and BLOCK_TAG_RE.search(lines[j]):
            return None
        m = TAGPARSE_RE.search(lines[j])
        if m:
            return m.group(1)
    return None


def parse_tags_from_file(file_path):
    """Yield (tag_name, data_type, line_no, parser_fn) for every tag the file parses. parser_fn is the
    TagParse.* function that reads the value (None when it can't be determined)."""
    tags = []
    if not os.path.exists(file_path):
        return tags

    with open(file_path, 'r', encoding='utf-8', errors='ignore') as fp:
        lines = fp.read().splitlines()

    for idx, line in enumerate(lines, 1):
        # Pattern 1: Dictionary entry: {"TagName", (s, o) => TagParse.TagTypeCheck(s, ref Var) }
        m_dict = re.search(r'\{\s*"([^"]+)"\s*,\s*\([^)]*\)\s*=>\s*TagParse\.(\w+)\(', line)
        if m_dict:
            tag_name = m_dict.group(1)
            parser_fn = m_dict.group(2)
            data_type = TYPE_MAP.get(parser_fn, parser_fn)
            # TagStringListCheck(s, false, ref x) is the overload that keeps commas: one entry per tag line.
            if parser_fn == 'TagStringListCheck' and re.search(r'TagStringListCheck\(\s*\w+\s*,\s*false\s*,', line):
                data_type = 'List<string> (one per tag line, commas kept)'
            tags.append((tag_name, data_type, idx, parser_fn))
            continue

        # Pattern 2: Dictionary entry with direct assignment or other helper
        m_dict2 = re.search(r'\{\s*"([^"]+)"\s*,\s*\([^)]*\)\s*=>', line)
        if m_dict2:
            tag_name = m_dict2.group(1)
            # Try to infer type
            if 'bool' in line.lower() or 'true' in line.lower() or 'false' in line.lower():
                dtype = 'bool (true/false)'
            elif 'list' in line.lower():
                dtype = 'List<string>'
            elif 'convert.to' in line.lower():
                dtype = 'numeric / enum'
            else:
                dtype = 'custom parse'
            tags.append((tag_name, dtype, idx, None))
            continue

        # Pattern 3: tag.StartsWith("[TagName:") or tag.Contains("[TagName:")
        # (a few parsers omit the bracket, e.g. RivalAI Spawn's Contains("SpawnGroups:"))
        # (and BehaviorManager tests customData.Contains("[BehaviorName:Fighter]") directly)
        # (and one parser omits the colon: StartsWith("[ContainerTypeAssignmentReference"))
        # (and aliases share a line: Contains("[WeaponsSystem:") || Contains("[WeaponSystem:"))
        names = (re.findall(r'\w+\.(?:StartsWith|Contains)\("\[([a-zA-Z0-9_]+)(?::|")', line)
                 or re.findall(r'tag\.(?:StartsWith|Contains)\("([a-zA-Z0-9_]+):"', line))
        if names:
            parser_fn = block_parser(lines, idx)
            dtype = TYPE_MAP.get(parser_fn, parser_fn) if parser_fn else 'custom / block parse'
        for tag_name in names:
            tags.append((tag_name, dtype, idx, parser_fn))

    return tags

def compute_dir_hash(path):
    hasher = hashlib.sha256()
    for root, _, files in sorted(os.walk(path)):
        for f in sorted(files):
            if f.endswith('.cs'):
                fpath = os.path.join(root, f)
                hasher.update(f.encode('utf-8'))
                try:
                    with open(fpath, 'rb') as fp:
                        hasher.update(fp.read())
                except Exception:
                    pass
    return hasher.hexdigest()[:16]

def get_git_commit(path):
    """HEAD commit of the MES clone (None for a Workshop copy), so drift can be diffed with git log."""
    try:
        out = subprocess.run(['git', '-C', path, 'log', '-1', '--format=%H|%cs|%s'],
                             capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return None
    if out.returncode != 0 or '|' not in out.stdout:
        return None
    sha, date, subject = out.stdout.strip().split('|', 2)
    return {'sha': sha, 'date': date, 'subject': subject}

def build_cache(mes_path):
    print(f"Scanning MES source at: {mes_path}")
    file_map = find_mes_files(mes_path)
    all_tags = []
    seen = set()

    for ptype, fpaths in sorted(file_map.items()):
        for fpath in fpaths:
            parsed = parse_tags_from_file(fpath)
            for tag_name, dtype, line_no, parser_fn in parsed:
                key = (ptype, tag_name.lower())
                if key in seen:
                    continue
                seen.add(key)
                entry = {
                    'profile': ptype,
                    'tag': tag_name,
                    'type': dtype,
                    'file': os.path.basename(fpath),
                    'line': line_no
                }
                if parser_fn:
                    entry['parser'] = parser_fn
                all_tags.append(entry)

    # Trigger types are string compares (trigger.Type == "Timer"), not an enum, so collect them here.
    trigger_types = set()
    trigger_dir = os.path.join(mes_path, 'Behavior', 'Subsystems', 'Trigger')
    for root, _, files in os.walk(trigger_dir):
        for f in files:
            if f.endswith('.cs'):
                with open(os.path.join(root, f), 'r', encoding='utf-8', errors='ignore') as fp:
                    trigger_types |= set(re.findall(r'\bType == "([A-Za-z]+)"', fp.read()))

    cache_data = {
        'values': {'RivalAI Trigger.Type': sorted(trigger_types)},
        'metadata': {
            'generated_at': datetime.now(timezone.utc).isoformat(),
            'mes_path': mes_path,
            'source_hash': compute_dir_hash(mes_path),
            'git_commit': get_git_commit(mes_path),
            'total_tags': len(all_tags),
            'total_profiles': len(file_map)
        },
        'tags': all_tags
    }

    with open(CACHE_FILE, 'w', encoding='utf-8') as fp:
        json.dump(cache_data, fp, indent=2)

    print(f"Successfully cached {len(all_tags)} tags across {len(file_map)} profiles to: {CACHE_FILE}")
    return cache_data

def load_cache():
    if os.path.exists(CACHE_FILE):
        try:
            with open(CACHE_FILE, 'r', encoding='utf-8') as fp:
                return json.load(fp)
        except Exception:
            return None
    return None

def main():
    parser = argparse.ArgumentParser(description='Query MES tags and profile configurations from MES source or offline cache.')
    parser.add_argument('-t', '--tag', help='Filter by tag name substring (case-insensitive)')
    parser.add_argument('-p', '--profile', help='Filter by profile type substring (e.g. Action, Condition, Event, Zone, Autopilot)')
    parser.add_argument('-e', '--exact', action='store_true', help='Exact tag name match')
    parser.add_argument('--path', help='Path to MES source code')
    parser.add_argument('--rebuild-cache', action='store_true', help='Rebuild offline tag cache from MES source')
    parser.add_argument('--json', action='store_true', help='Output results as JSON (token-lean for agent scripts)')
    args = parser.parse_args()

    mes_path = resolve_mes_path(args.path) if args.path else detect_mes_path()

    if args.rebuild_cache:
        if not mes_path or not os.path.isdir(mes_path):
            print("[ERROR] Cannot rebuild cache: No valid MES source path found.")
            sys.exit(1)
        build_cache(mes_path)
        return

    cache = load_cache()

    if not cache:
        if mes_path and os.path.isdir(mes_path):
            cache = build_cache(mes_path)
        else:
            print("[ERROR] No offline cache found and no MES source directory detected.")
            print("Please specify --path to your MES source code to generate the initial cache.")
            sys.exit(1)

    tags = cache.get('tags', [])
    results = []

    for item in tags:
        ptype = item['profile']
        tname = item['tag']
        dtype = item['type']
        fname = item['file']
        line = item['line']

        if args.profile and args.profile.lower() not in ptype.lower():
            continue

        if args.tag:
            if args.exact:
                if args.tag.lower() != tname.lower():
                    continue
            else:
                if args.tag.lower() not in tname.lower():
                    continue

        results.append(item)

    if args.json:
        print(json.dumps(results, indent=2))
        return

    if not results:
        print("No matching tags found.")
        return

    print(f"\nFound {len(results)} matching tag(s) (Cache: {cache.get('metadata', {}).get('source_hash', 'unknown')}):\n")
    print(f"{'Profile Type':<24} | {'Tag Name':<38} | {'Expected Data Type':<30} | Source")
    print("-" * 120)

    for item in results:
        ptype = item['profile']
        tname = item['tag']
        dtype = item['type']
        fname = item['file']
        line = item['line']
        tag_str = f"[{tname}:...]"
        print(f"{ptype:<24} | {tag_str:<38} | {dtype:<30} | {fname}:{line}")

    print()

if __name__ == '__main__':
    main()
