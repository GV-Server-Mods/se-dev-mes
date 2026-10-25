#!/usr/bin/env python3
"""
audit_prefab_thrust.py — Directional Thruster & Behavior Auditor for Space Engineers Prefabs.

Audits prefab SBC XML files to verify directional thruster coverage relative to the
Primary Remote Control block orientation, detecting critical failure modes:
1. Missing Backward (Braking) Thrusters -> no braking: overshoots waypoints and swings back
   (MES 2.75.00+; before 2.75.00 it could run away into space).
2. Missing Lateral / Vertical Thrusters -> strafe drift, no dampener correction on that side.
3. Rover / Ground Vehicle Thrusters    -> Missing Down (downforce), or Up when level mode is on.
4. FighterPlane Single-Axis Validation -> Permits forward-only thrust on planets.
5. Level Mode                         -> Notes which autopilots set [FlyLevelWithGravity] / [LevelWithGravityWhenIdle].

Behaviors are resolved the way MES assigns them: spawn group <Prefab SubtypeId> -> <Behaviour>
-> [RivalAI Behavior] profile ([BehaviorName:], [AutopilotData:] and the Secondary/Tertiary
slots) -> [RivalAI Autopilot] profiles (level-mode flags). Legacy [BehaviorName:] in the remote
control's Custom Data is still read. Prefabs no spawn group gives a behavior are skipped.
Only thrusters on the remote control's grid are counted (MES ignores subgrid thrust unless
[UseSubgridThrust:true]).

Usage:
  python audit_prefab_thrust.py --path "Data/Prefabs"          (profiles read from the parent Data folder)
  python audit_prefab_thrust.py --path "Data/Prefabs" --data "Data"
  python audit_prefab_thrust.py --strict
  python audit_prefab_thrust.py --json
"""

import os
import sys
import re
import json
import argparse
import xml.etree.ElementTree as ET

DIR_VECTORS = {
    "Forward":  (0, 0, -1),
    "Backward": (0, 0, 1),
    "Left":     (-1, 0, 0),
    "Right":    (1, 0, 0),
    "Up":       (0, 1, 0),
    "Down":     (0, -1, 0),
}

def cross_product(v1, v2):
    return (
        v1[1] * v2[2] - v1[2] * v2[1],
        v1[2] * v2[0] - v1[0] * v2[2],
        v1[0] * v2[1] - v1[1] * v2[0]
    )

def negate_vector(v):
    return (-v[0], -v[1], -v[2])

def get_remote_basis(forward_str, up_str):
    f = DIR_VECTORS.get(forward_str, (0, 0, -1))
    u = DIR_VECTORS.get(up_str, (0, 1, 0))
    b = negate_vector(f)
    d = negate_vector(u)
    r = cross_product(f, u)
    l = negate_vector(r)
    return {
        "Forward":  f,
        "Backward": b,
        "Up":       u,
        "Down":     d,
        "Right":    r,
        "Left":     l
    }

def classify_thrust_direction(thrust_forward_str, remote_basis):
    """
    In Space Engineers (ThrusterProfile.cs:90-128):
    Thruster exhaust points out the back (+Forward in block space).
    Therefore, a thruster whose Forward matches remote Backward pushes the grid Forward.
    """
    th_f = DIR_VECTORS.get(thrust_forward_str, (0, 0, -1))
    if th_f == remote_basis["Backward"]:
        return "Forward"
    if th_f == remote_basis["Forward"]:
        return "Backward"
    if th_f == remote_basis["Down"]:
        return "Up"
    if th_f == remote_basis["Up"]:
        return "Down"
    if th_f == remote_basis["Left"]:
        return "Right"
    if th_f == remote_basis["Right"]:
        return "Left"
    return "Unknown"

def extract_custom_data_behavior(custom_data_text):
    if not custom_data_text:
        return None, []
    behavior_match = re.search(r'\[BehaviorName:\s*([^\]]+)\]', custom_data_text)
    behavior = behavior_match.group(1).strip() if behavior_match else None
    
    tags = []
    if re.search(r'\[FlyLevelWithGravity:\s*true\]', custom_data_text, re.IGNORECASE):
        tags.append("FlyLevelWithGravity")
    if re.search(r'\[LevelWithGravityWhenIdle:\s*true\]', custom_data_text, re.IGNORECASE):
        tags.append("LevelWithGravityWhenIdle")
    return behavior, tags

PROFILE_RE = re.compile(r'<SubtypeId>([^<]+)</SubtypeId>\s*</Id>\s*<Description>(.*?)</Description>', re.S)
SPAWN_PREFAB_RE = re.compile(r'<Prefab\s+SubtypeId="([^"]+)"\s*>(.*?)</Prefab>', re.S)
LEVEL_TAGS = ("FlyLevelWithGravity", "LevelWithGravityWhenIdle")

def load_behavior_map(data_dir):
    """Prefab SubtypeId -> list of {profile, name, level_tags}, resolved like MES does."""
    behaviors, autopilots, prefab_behaviors = {}, {}, {}
    for root, _, files in os.walk(data_dir):
        for f in files:
            if not f.endswith(".sbc"):
                continue
            try:
                with open(os.path.join(root, f), encoding="utf-8-sig", errors="ignore") as h:
                    text = h.read()
            except OSError:
                continue
            for m in PROFILE_RE.finditer(text):
                sid, desc = m.group(1).strip(), m.group(2)
                if re.search(r'\[(RivalAI|MES AI) Behavior\]', desc):
                    name = re.search(r'\[BehaviorName:\s*([^\]]+)\]', desc)
                    slots = re.findall(r'\[(?:Secondary|Tertiary)?AutopilotData:\s*([^\]]+)\]', desc)
                    behaviors[sid] = (name.group(1).strip() if name else None, [s.strip() for s in slots])
                elif re.search(r'\[(RivalAI|MES AI) Autopilot\]', desc):
                    autopilots[sid] = [t for t in LEVEL_TAGS if re.search(r'\[' + t + r':\s*true\]', desc, re.I)]
            for m in SPAWN_PREFAB_RE.finditer(text):
                b = re.search(r'<Behaviour>\s*([^<]+?)\s*</Behaviour>', m.group(2))
                if b:
                    prefab_behaviors.setdefault(m.group(1).strip(), set()).add(b.group(1))
    result = {}
    for prefab, profiles in prefab_behaviors.items():
        for profile in sorted(profiles):
            name, slots = behaviors.get(profile, (None, []))
            tags = sorted({t for s in slots for t in autopilots.get(s, [])})
            sources = ["%s (%s)" % (s, "/".join(autopilots[s])) for s in slots if autopilots.get(s)]
            result.setdefault(prefab, []).append({"profile": profile, "name": name, "level_tags": tags, "level_sources": sources})
    return result

def audit_prefab_file(file_path, behavior_map):
    results = []
    try:
        tree = ET.parse(file_path)
        root = tree.getroot()
    except Exception as e:
        return [{"file": file_path, "status": "ERROR", "message": f"XML parse failure: {e}"}]

    # Locate Prefab definitions
    prefabs = root.findall(".//Prefab")
    if not prefabs and root.tag.endswith("Prefab"):
        prefabs = [root]
    if not prefabs and root.findall(".//CubeGrids"):
        prefabs = [root]

    for p in prefabs:
        # Prefab files write <Id Type=".." Subtype=".." />; older ones <Id><SubtypeId>..</SubtypeId></Id>
        id_el = p.find("Id")
        subtype_el = p.find(".//Id/SubtypeId")
        if subtype_el is not None and subtype_el.text:
            prefab_id = subtype_el.text.strip()
        elif id_el is not None and id_el.get("Subtype"):
            prefab_id = id_el.get("Subtype").strip()
        else:
            prefab_id = os.path.splitext(os.path.basename(file_path))[0]

        # Prefab files name each grid <CubeGrid>; blueprints and saves use MyObjectBuilder_CubeGrid
        grids = p.findall("./CubeGrids/CubeGrid") + p.findall(".//MyObjectBuilder_CubeGrid")
        if not grids:
            continue

        for g_idx, grid in enumerate(grids):
            grid_name_el = grid.find("CustomName")
            grid_name = grid_name_el.text if grid_name_el is not None and grid_name_el.text else f"Grid_{g_idx+1}"

            # Check for wheels (rover indication)
            wheels = grid.findall(".//MyObjectBuilder_CubeBlock[@xsi:type='MyObjectBuilder_MotorSuspension']",
                                  {'xsi': 'http://www.w3.org/2001/XMLSchema-instance'})
            if not wheels:
                wheels = [b for b in grid.findall(".//MyObjectBuilder_CubeBlock") if "MotorSuspension" in b.get("{http://www.w3.org/2001/XMLSchema-instance}type", "")]

            is_wheeled_grid = len(wheels) > 0

            # Find Remote Controls
            remotes = grid.findall(".//MyObjectBuilder_CubeBlock[@xsi:type='MyObjectBuilder_RemoteControl']",
                                   {'xsi': 'http://www.w3.org/2001/XMLSchema-instance'})
            if not remotes:
                remotes = [b for b in grid.findall(".//MyObjectBuilder_CubeBlock") if "RemoteControl" in b.get("{http://www.w3.org/2001/XMLSchema-instance}type", "")]

            if not remotes:
                # No remote control on this grid
                continue

            primary_remote = remotes[0]
            orient_el = primary_remote.find("BlockOrientation")
            rc_forward = orient_el.get("Forward", "Forward") if orient_el is not None else "Forward"
            rc_up = orient_el.get("Up", "Up") if orient_el is not None else "Up"
            basis = get_remote_basis(rc_forward, rc_up)

            custom_data_el = primary_remote.find("CustomData")
            custom_data = custom_data_el.text if custom_data_el is not None else ""
            legacy_behavior, legacy_tags = extract_custom_data_behavior(custom_data)
            assigned = behavior_map.get(prefab_id, [])
            if not assigned and legacy_behavior:
                assigned = [{"profile": "remote Custom Data", "name": legacy_behavior, "level_tags": legacy_tags,
                             "level_sources": ["remote Custom Data (%s)" % "/".join(legacy_tags)] if legacy_tags else []}]
            if not assigned:
                # No spawn group gives this prefab a behavior (statics, wrecks, unused prefabs)
                continue

            # Find Thrusters
            thrusters = grid.findall(".//MyObjectBuilder_CubeBlock[@xsi:type='MyObjectBuilder_Thrust']",
                                     {'xsi': 'http://www.w3.org/2001/XMLSchema-instance'})
            if not thrusters:
                thrusters = [b for b in grid.findall(".//MyObjectBuilder_CubeBlock") if "Thrust" in b.get("{http://www.w3.org/2001/XMLSchema-instance}type", "")]

            thrust_counts = {
                "Forward": 0,
                "Backward": 0,
                "Up": 0,
                "Down": 0,
                "Left": 0,
                "Right": 0,
                "Unknown": 0
            }

            for t in thrusters:
                t_orient = t.find("BlockOrientation")
                t_forward = t_orient.get("Forward", "Forward") if t_orient is not None else "Forward"
                effective_dir = classify_thrust_direction(t_forward, basis)
                thrust_counts[effective_dir] += 1

            # One entry per distinct BehaviorName; level flags merged across the profiles using it
            by_name = {}
            for a in assigned:
                entry = by_name.setdefault(a["name"], {"profiles": [], "tags": set(), "sources": []})
                entry["profiles"].append(a["profile"])
                entry["tags"].update(a["level_tags"])
                entry["sources"] += [x for x in a["level_sources"] if x not in entry["sources"]]
            for name, entry in by_name.items():
                if name is None or name == "Passive":
                    # Passive grids never navigate (stations, installations, wrecks); without a
                    # BehaviorName MES finds no subclass (BehaviorManager.GetSubclassFromCustomData)
                    continue
                results.append({
                    "file": file_path,
                    "prefab": prefab_id,
                    "grid": grid_name,
                    "remote_orientation": f"Fwd={rc_forward}, Up={rc_up}",
                    "behavior": name,
                    "behavior_profiles": entry["profiles"],
                    "is_wheeled": is_wheeled_grid,
                    "thrust_counts": thrust_counts,
                    "warning_tags": sorted(entry["tags"]),
                    "level_sources": entry["sources"]
                })

    return results

def evaluate_grid_thrust(grid_data):
    issues = []
    behavior = grid_data.get("behavior")
    counts = grid_data.get("thrust_counts", {})
    is_wheeled = grid_data.get("is_wheeled", False)
    tags = grid_data.get("warning_tags", [])

    # Level mode: pitch aims at level instead of the target (RotationSystem.cs:187). Intended for
    # turret-only hovers and cargo ships; a problem for craft that must pitch at targets.
    if tags:
        issues.append({
            "severity": "INFO",
            "type": "LEVEL_MODE",
            "message": "Level mode in " + ", ".join(grid_data.get("level_sources") or tags) + ": pitch holds level there, so the nose can't dive or climb at targets (RotationSystem.cs:187). Fine for turret-only hovers and cargo ships."
        })

    # Behavior specific evaluation
    if behavior == "FighterPlane":
        if counts.get("Forward", 0) == 0:
            issues.append({
                "severity": "CRITICAL",
                "type": "MISSING_FORWARD_THRUST",
                "message": "FighterPlane requires at least 1 Forward thruster for attack runs."
            })
        if counts.get("Backward", 0) == 0 and counts.get("Left", 0) == 0 and counts.get("Up", 0) == 0:
            issues.append({
                "severity": "INFO",
                "type": "SINGLE_AXIS_PLANE",
                "message": "FighterPlane uses single-axis forward propulsion. Valid for planetary flight; will fail in zero-G space."
            })
    elif is_wheeled or behavior in ["Rover", "FakeRover"]:
        # Rover evaluation
        if counts.get("Down", 0) == 0:
            issues.append({
                "severity": "WARNING",
                "type": "MISSING_DOWNFORCE_THRUST",
                "message": "Thrust-driven rover has NO Down thrusters. Downward thrusters provide artificial downforce against suspension bounce on rough terrain."
            })
        if counts.get("Up", 0) == 0 and ("FlyLevelWithGravity" in tags or "LevelWithGravityWhenIdle" in tags):
            issues.append({
                "severity": "WARNING",
                "type": "MISSING_ALTITUDE_CLAMP_THRUST",
                "message": "Rover in level mode has NO Up thrusters. CalculateHoverThrust() holds altitude with up/down thrust; without level mode MES never commands Up thrust."
            })
        if counts.get("Backward", 0) == 0:
            issues.append({
                "severity": "WARNING",
                "type": "MISSING_BRAKING_THRUST",
                "message": "Rover has NO Backward (braking) thrusters. CalculateStoppingDistance() will return 0, preventing deceleration before waypoint turns."
            })
        if counts.get("Forward", 0) == 0:
            issues.append({
                "severity": "CRITICAL",
                "type": "MISSING_FORWARD_THRUST",
                "message": "Rover has NO Forward thrusters for locomotion."
            })
    elif behavior == "Passive":
        # Passive grids don't navigate
        pass
    else:
        # Standard 3D Space / Hover Behaviors (Fighter, Strike, Horsefly, Sniper, Patrol, Hunter, etc.)
        if counts.get("Backward", 0) == 0:
            issues.append({
                "severity": "WARNING",
                "type": "NO_BRAKING_THRUST",
                "message": f"Grid has NO Backward (braking) thrusters. Under behavior '{behavior or 'Default'}', stopping distance is 0, so it overshoots waypoints at full speed and swings back (MES 2.75.00+). Before 2.75.00 this could run away into space."
            })
        missing_dirs = [d for d in ["Forward", "Up", "Down", "Left", "Right"] if counts.get(d, 0) == 0]
        if missing_dirs:
            issues.append({
                "severity": "WARNING",
                "type": "MISSING_CARDINAL_THRUST",
                "message": f"Grid is missing thrusters in directions: {', '.join(missing_dirs)}. Strafing toward a missing side drifts uncontrolled, dampeners can't stop drift that way, and level mode can't hold altitude without Up/Down."
            })

    return issues

def main():
    parser = argparse.ArgumentParser(description="Audit Space Engineers prefabs for directional thruster coverage and behavior compatibility.")
    parser.add_argument("--path", "-p", default=".", help="Path to search for prefab .sbc files (defaults to current directory).")
    parser.add_argument("--data", "-d", default=None, help="Mod Data folder holding spawn groups, behaviors and autopilots (defaults to the parent of a Prefabs folder, else --path).")
    parser.add_argument("--strict", "-s", action="store_true", help="Treat warnings as errors.")
    parser.add_argument("--json", "-j", action="store_true", help="Output results in JSON format.")
    args = parser.parse_args()

    target_dir = os.path.abspath(args.path)
    if not os.path.exists(target_dir):
        print(f"[ERROR] Target path does not exist: {target_dir}")
        sys.exit(2)

    if args.data:
        data_dir = os.path.abspath(args.data)
    elif os.path.basename(target_dir).lower() == "prefabs":
        data_dir = os.path.dirname(target_dir)
    else:
        data_dir = target_dir
    behavior_map = load_behavior_map(data_dir)

    prefab_files = []
    for root, _, files in os.walk(target_dir):
        for f in files:
            if f.endswith(".sbc") and not f.endswith(".sbcB5"):
                full_path = os.path.join(root, f)
                prefab_files.append(full_path)

    all_audits = []
    total_errors = 0
    total_warnings = 0

    for pf in prefab_files:
        grid_audits = audit_prefab_file(pf, behavior_map)
        for g in grid_audits:
            if "status" in g and g["status"] == "ERROR":
                total_errors += 1
                continue
            issues = evaluate_grid_thrust(g)
            g["issues"] = issues
            for iss in issues:
                if iss["severity"] in ["CRITICAL", "ERROR"]:
                    total_errors += 1
                elif iss["severity"] == "WARNING":
                    total_warnings += 1
            all_audits.append(g)

    if args.json:
        output = {
            "summary": {
                "prefabs_scanned": len(prefab_files),
                "grids_audited": len(all_audits),
                "errors": total_errors,
                "warnings": total_warnings
            },
            "audits": all_audits
        }
        print(json.dumps(output, indent=2))
        sys.exit(1 if (total_errors > 0 or (args.strict and total_warnings > 0)) else 0)

    print("=" * 70)
    print(" Space Engineers Prefab Thruster & Behavior Auditor")
    print("=" * 70)
    print(f"Target Directory: {target_dir}")
    print(f"Profiles From:    {data_dir}")
    print(f"Prefabs Scanned:  {len(prefab_files)}")
    print(f"Prefabs With AI:  {len(behavior_map)}")
    print(f"Grids Audited:    {len(all_audits)}")
    print("-" * 70)

    for g in all_audits:
        c = g["thrust_counts"]
        level = f", level mode: {'/'.join(g['warning_tags'])}" if g["warning_tags"] else ""
        print(f"\n[{g['prefab']}] -> {g['grid']} (Behavior: {g['behavior'] or 'no BehaviorName'}{level})")
        print(f"  Behavior Profiles:  {', '.join(g['behavior_profiles'])}")
        print(f"  Remote Orientation: {g['remote_orientation']}")
        print(f"  Thrust Coverage:    Fwd={c['Forward']} | Back(Brake)={c['Backward']} | Up={c['Up']} | Down={c['Down']} | Left={c['Left']} | Right={c['Right']}")
        
        issues = g.get("issues", [])
        if not issues:
            print("  [PASS] All required thruster directions present.")
        else:
            for iss in issues:
                prefix = f"  [{iss['severity']}] {iss['type']}:"
                print(f"{prefix} {iss['message']}")

    print("\n" + "=" * 70)
    if total_errors == 0 and (total_warnings == 0 or not args.strict):
        print(f"[PASS] Prefab thruster audit passed ({total_errors} errors, {total_warnings} warnings).")
        sys.exit(0)
    else:
        print(f"[FAIL] Prefab thruster audit failed ({total_errors} errors, {total_warnings} warnings).")
        sys.exit(1)

if __name__ == "__main__":
    main()

