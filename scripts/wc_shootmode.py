#!/usr/bin/env python3
"""
wc_shootmode.py - list / set the WeaponCore "shoot mode" stored inside prefab (.sbc) files.

Why: MES fires WeaponCore fixed guns with ToggleWeaponFire. WeaponCore ignores that command while the gun is
in its default mode "Auto (AI Controlled)" (AiShoot), so MES aims at the target and the guns never fire.
The mode is saved per block in the prefab as protobuf inside the block's ModStorageComponent
(key 75bbb4f5-4fb9-4230-beef-bb79c9811501); it is field 28 of the weapon "Overrides" message
(0 = AiShoot is the default and is omitted). See references/aircraft_behaviors_and_tuning.md, section 5B.

Modes (WeaponCore ShootManager.ShootModes): ai=0, mouse=1, toggle=2, fire=3.
Only `mouse` has been confirmed to make MES-driven fixed guns fire in game.

Commands:
  wc_shootmode.py list PATH [PATH ...]
      Show every WeaponCore block in the prefab files and its current mode.
  wc_shootmode.py set --mode mouse --subtypes CAP_50Cal,CAP_50CalOffset PATH [PATH ...] [--apply] [--backup-dir DIR] [--delete-b5]
      Set the mode on blocks whose SubtypeName is in --subtypes. Dry run unless --apply.
      --delete-b5 removes the stale `<file>.sbcB5` cache next to each changed prefab (the game keeps
      spawning the cached copy otherwise).
  wc_shootmode.py classify --mods DIR SUBTYPE [SUBTYPE ...]
      Look up each weapon SubtypeId in the WeaponCore definition files (*.cs) under DIR and say whether it is a
      TURRET (leave on Auto), a FIXED-TRACKING gun (fires itself on Auto, or by MES on Mouse Control) or a
      FIXED gun (never fires on Auto: MES-flown grids need Mouse Control).
      DIR is e.g. C:/Program Files (x86)/Steam/steamapps/workshop/content/244850
  wc_shootmode.py audit --mods DIR [--exclude GLOB ...] PATH [PATH ...]
      Lint: warn on every FIXED gun left on Auto (exit 1). Use --exclude for prefabs MES never fires,
      e.g. static wrecks: --exclude "NW* *.sbc".

PATH can be files or folders (searched recursively for *.sbc). Only blocks carrying the WeaponCore storage
key are touched; the Overrides message is located by structure (the message holding varint fields 26 and 27),
not by a fixed offset, and a block whose layout is not recognised is reported and skipped.
"""
import argparse
import base64
import fnmatch
import glob
import os
import re
import shutil
import sys

KEY = "75bbb4f5-4fb9-4230-beef-bb79c9811501"
FIELD = 28
MODES = {"ai": 0, "mouse": 1, "toggle": 2, "fire": 3}
NAMES = {v: k for k, v in MODES.items()}


# ---- minimal protobuf reader/writer -------------------------------------------------------------------------
def _rv(b, i):
    r = s = 0
    while True:
        c = b[i]
        i += 1
        r |= (c & 0x7F) << s
        s += 7
        if not c & 0x80:
            return r, i


def _wv(n):
    o = bytearray()
    while True:
        c = n & 0x7F
        n >>= 7
        if n:
            o.append(c | 0x80)
        else:
            o.append(c)
            return bytes(o)


def parse(b):
    f, i = [], 0
    while i < len(b):
        t, i = _rv(b, i)
        num, wt = t >> 3, t & 7
        if wt == 0:
            v, i = _rv(b, i)
        elif wt == 2:
            n, i = _rv(b, i)
            if i + n > len(b):
                raise ValueError("length overruns message")
            v = b[i:i + n]
            i += n
        elif wt == 1:
            v = b[i:i + 8]
            i += 8
        elif wt == 5:
            v = b[i:i + 4]
            i += 4
        else:
            raise ValueError("unsupported wire type %d" % wt)
        f.append([num, wt, v])
    return f


def build(f):
    o = bytearray()
    for num, wt, v in f:
        o += _wv(num << 3 | wt)
        if wt == 0:
            o += _wv(v)
        elif wt == 2:
            o += _wv(len(v)) + v
        else:
            o += v
    return bytes(o)


def find_overrides(buf, path=()):
    """Return paths (tuples of field numbers) of every message that holds varint fields 26 and 27."""
    try:
        fields = parse(buf)
    except (ValueError, IndexError):
        return []
    nums = {f[0] for f in fields if f[1] == 0}
    hits = [path] if (26 in nums and 27 in nums) else []
    for num, wt, v in fields:
        if wt == 2 and len(v) > 2:
            hits += find_overrides(v, path + (num,))
    return hits


def _descend(fields, path, fn):
    if not path:
        return fn(fields)
    for x in fields:
        if x[0] == path[0] and x[1] == 2:
            inner = parse(x[2])
            res = _descend(inner, path[1:], fn)
            if res is not None:
                x[2] = build(inner)
            return res
    raise ValueError("path missing")


def get_mode(blob):
    paths = find_overrides(blob)
    if len(paths) != 1:
        return None, "layout not recognised (%d candidate messages)" % len(paths)
    fields = parse(blob)
    out = []
    _descend(fields, paths[0], lambda inner: out.append(next((x[2] for x in inner if x[0] == FIELD and x[1] == 0), 0)))
    return out[0], None


def set_mode(blob, mode):
    """Return the new blob, or None if it already has that mode. Raises ValueError if the layout is unknown."""
    paths = find_overrides(blob)
    if len(paths) != 1:
        raise ValueError("layout not recognised (%d candidate messages)" % len(paths))
    fields = parse(blob)
    changed = []

    def edit(inner):
        cur = next((x for x in inner if x[0] == FIELD and x[1] == 0), None)
        if cur is None and mode == 0:
            return False
        if cur is not None and cur[2] == mode:
            return False
        if mode == 0:
            inner[:] = [x for x in inner if not (x[0] == FIELD and x[1] == 0)]
        elif cur is not None:
            cur[2] = mode
        else:
            idx = max((k for k, x in enumerate(inner) if x[0] < FIELD), default=-1) + 1
            inner.insert(idx, [FIELD, 0, mode])
        changed.append(True)
        return True

    _descend(fields, paths[0], edit)
    return build(fields) if changed else None


# ---- prefab file handling -----------------------------------------------------------------------------------
def sbc_files(paths):
    for p in paths:
        if os.path.isdir(p):
            for dp, _, fns in os.walk(p):
                for fn in sorted(fns):
                    if fn.lower().endswith(".sbc"):
                        yield os.path.join(dp, fn)
        else:
            yield from glob.glob(p) or [p]


BLOCK_START = "<MyObjectBuilder_CubeBlock "
ITEM_RE = re.compile(r"<Key>%s</Key>(\s*)<Value>([^<]*)</Value>" % re.escape(KEY))


def wc_blocks(text):
    """Yield (subtype, min_xyz, value_start, value_end, base64_value) for each block with the WeaponCore key."""
    for m in ITEM_RE.finditer(text):
        blk = text.rfind(BLOCK_START, 0, m.start())
        seg = text[blk:m.start()]
        st = re.search(r"<SubtypeName>([^<]*)</SubtypeName>", seg)
        mn = re.search(r'<Min x="(-?\d+)" y="(-?\d+)" z="(-?\d+)"', seg)
        yield (st.group(1) if st else "?", ",".join(mn.groups()) if mn else "?", m.start(2), m.end(2), m.group(2))


def read_text(path):
    raw = open(path, "rb").read()
    return raw.startswith(b"\xef\xbb\xbf"), raw.decode("utf-8-sig")


def cmd_list(a):
    n = 0
    for f in sbc_files(a.paths):
        bom, text = read_text(f)
        rows = []
        for st, mn, s, e, val in wc_blocks(text):
            try:
                mode, err = get_mode(base64.b64decode(val))
            except (ValueError, IndexError):
                mode, err = None, "unreadable storage value"
            rows.append((st, mn, NAMES.get(mode, "?") if err is None else "? (%s)" % err))
        if rows:
            print(f)
            for st, mn, m in rows:
                print("  %-34s (%s)  %s" % (st, mn, m))
                n += 1
    print("\n%d WeaponCore block(s)." % n)
    return 0


def cmd_set(a):
    mode = MODES[a.mode]
    subs = {s.strip() for s in a.subtypes.split(",") if s.strip()}
    total = skipped = 0
    for f in sbc_files(a.paths):
        bom, text = read_text(f)
        edits, notes = [], []
        for st, mn, s, e, val in wc_blocks(text):
            if st not in subs:
                continue
            try:
                new = set_mode(base64.b64decode(val), mode)
            except (ValueError, IndexError) as ex:
                notes.append("SKIP %s (%s): %s" % (st, mn, ex))
                skipped += 1
                continue
            if new is None:
                notes.append("already %s: %s (%s)" % (a.mode, st, mn))
            else:
                edits.append((s, e, base64.b64encode(new).decode()))
                notes.append("%s %s (%s) -> %s" % ("set" if a.apply else "would set", st, mn, a.mode))
        if not notes:
            continue
        print(f)
        for n in notes:
            print("  " + n)
        total += len(edits)
        if a.apply and edits:
            for s, e, v in reversed(edits):
                text = text[:s] + v + text[e:]
            if a.backup_dir:
                os.makedirs(a.backup_dir, exist_ok=True)
                shutil.copy2(f, os.path.join(a.backup_dir, os.path.basename(f)))
            open(f, "wb").write((("\ufeff" if bom else "") + text).encode("utf-8"))
            b5 = f + "B5"
            if os.path.exists(b5):
                if a.delete_b5:
                    os.remove(b5)
                    print("  deleted stale cache " + os.path.basename(b5))
                else:
                    print("  NOTE: %s exists - delete it or the game may keep spawning the cached copy" % os.path.basename(b5))
    print("\n%s %d block(s)%s." % ("Changed" if a.apply else "Would change", total, (", skipped %d" % skipped) if skipped else ""))
    if not a.apply and total:
        print("Dry run. Re-run with --apply to write.")
    return 0


# ---- weapon definition classification ---------------------------------------------------------------------
# TURRET:         TurretAttached = true. WeaponCore aims and fires it; leave on Auto.
# FIXED-TRACKING: fixed, TrackTargets = true. Picks and fires at its own targets on Auto (MES commands are then
#                 ignored); Mouse Control hands firing to MES instead. Either can be right.
# FIXED:          fixed, TrackTargets = false. On Auto it never fires; MES-flown grids need Mouse Control.
# FLARE:          any weapon firing anti-smart ammo (WC2 Ewar AntiSmart/AntiSmartv2, or WC1 AreaEffect AntiSmart).
#                 Keep it off Mouse Control: MES can't recognise WC2 flares and would fire them as a plain fixed gun.
CLASS_HELP = {
    "FLARE": "FLARE          (keep on Auto; self-target with LockedSmartOnly, see third_party_integrations 1F)",
    "TURRET": "TURRET         (leave on Auto)",
    "FIXED-TRACKING": "FIXED-TRACKING (fires itself on Auto; Mouse Control lets MES fire it)",
    "FIXED": "FIXED          (never fires on Auto; needs Mouse Control for MES)",
}
AI_PRESET_RE = re.compile(r"\bAiDef\s+(\w+)\s*(?:=>|=)\s*new\s+AiDef\s*\{(.*?)\}", re.S)
WEAPON_RE = re.compile(r"\bWeaponDefinition\s+\w+\s*=>\s*new\s+WeaponDefinition\b")
AMMO_RE = re.compile(r"\bAmmoDef\s+(\w+)\s*(?:=>|=)")


def _flag(body, key):
    m = re.search(key + r"\s*=\s*(true|false)", body)
    return m.group(1) if m else "?"


def load_classes(mods):
    """Map weapon block SubtypeId -> (class, TrackTargets, TurretAttached, file) from WeaponCore *.cs definitions.

    Handles shared AiDef presets (`Ai = Common_..._Ai_BasicTurret`, defined in another file) and every SubtypeId
    listed under a definition's MountPoints (e.g. a player block plus its `_NPC` copy)."""
    texts = []
    for f in glob.glob(os.path.join(mods, "**", "*.cs"), recursive=True):
        if re.search(r"[\\/](bin|obj)[\\/]", f):
            continue
        try:
            texts.append((f, open(f, encoding="utf-8-sig", errors="replace").read()))
        except OSError:
            pass
    presets = {}
    for _, t in texts:
        for m in AI_PRESET_RE.finditer(t):
            presets[m.group(1)] = (_flag(m.group(2), "TrackTargets"), _flag(m.group(2), "TurretAttached"))
    antismart = set()
    for _, t in texts:
        heads = list(AMMO_RE.finditer(t))
        for i, m in enumerate(heads):
            body = t[m.end():heads[i + 1].start() if i + 1 < len(heads) else len(t)]
            if re.search(r"Type\s*=\s*AntiSmart|AreaEffect\s*=\s*AntiSmart\b", body):
                antismart.add(m.group(1))
    out = {}
    for f, t in texts:
        starts = [m.start() for m in WEAPON_RE.finditer(t)] + [len(t)]
        for s, e in zip(starts, starts[1:]):
            d = t[s:e]
            mp = re.search(r"MountPoints\s*=\s*new\s*\[\]\s*\{(.*?)\bMuzzles\s*=", d, re.S)
            subs = re.findall(r'SubtypeId\s*=\s*"([^"]+)"', mp.group(1) if mp else d[:4000])
            ai = re.search(r"\bAi\s*=\s*(\w+)\s*,", d)
            if ai and ai.group(1) != "new":
                tt, ta = presets.get(ai.group(1), ("?", "?"))
            else:
                inline = re.search(r"\bAi\s*=\s*new\s+AiDef\s*\{(.*?)\}", d, re.S)
                tt, ta = (_flag(inline.group(1), "TrackTargets"), _flag(inline.group(1), "TurretAttached")) if inline else ("?", "?")
            cls = "TURRET" if ta == "true" else "FIXED-TRACKING" if (ta, tt) == ("false", "true") else "FIXED" if ta == "false" else "?"
            ammos = re.search(r"\bAmmos\s*=\s*new\s*\[\]\s*\{([^}]*)\}", d)
            if ammos and antismart & set(re.findall(r"\w+", ammos.group(1))):
                cls = "FLARE"
            for sub in subs:
                out.setdefault(sub, (cls, tt, ta, f))
    return out


def cmd_classify(a):
    defs = load_classes(a.mods)
    for s in a.subtypes:
        c = defs.get(s)
        if not c:
            print("%-36s no WeaponCore definition found under %s" % (s, a.mods))
            continue
        print("%-36s %s  [TrackTargets=%s TurretAttached=%s]  %s" % (s, CLASS_HELP.get(c[0], "unclear"), c[1], c[2], os.path.basename(c[3])))
    return 0


def cmd_audit(a):
    """Flag FIXED guns left on Auto (they never fire on an MES-flown grid) and FLAREs taken off Auto."""
    defs = load_classes(a.mods)
    warn = info = 0
    for f in sbc_files(a.paths):
        name = os.path.basename(f)
        if any(fnmatch.fnmatch(name, pat) for pat in a.exclude):
            continue
        _, text = read_text(f)
        rows = []
        for st, mn, s, e, val in wc_blocks(text):
            c = defs.get(st)
            if not c or c[0] not in ("FIXED", "FIXED-TRACKING", "FLARE"):
                continue
            try:
                mode, err = get_mode(base64.b64decode(val))
            except (ValueError, IndexError):
                mode, err = None, "unreadable storage value"
            if err:
                rows.append("  INFO %-34s (%s) %s; shoot mode not readable" % (st, mn, c[0]))
                info += 1
            elif c[0] == "FIXED" and mode == MODES["ai"]:
                rows.append("  WARN %-34s (%s) FIXED gun on Auto: never fires; set --mode mouse" % (st, mn))
                warn += 1
            elif c[0] == "FLARE" and mode != MODES["ai"]:
                rows.append("  WARN %-34s (%s) FLARE on %s: MES fires it like a plain gun; set --mode ai" % (st, mn, NAMES.get(mode, mode)))
                warn += 1
        if rows:
            print(f)
            print("\n".join(rows))
    print("\n%d warning(s), %d unreadable." % (warn, info))
    return 1 if warn else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("list")
    p.add_argument("paths", nargs="+")
    p.set_defaults(fn=cmd_list)
    p = sub.add_parser("set")
    p.add_argument("--mode", required=True, choices=sorted(MODES))
    p.add_argument("--subtypes", required=True, help="comma-separated block SubtypeNames")
    p.add_argument("--apply", action="store_true")
    p.add_argument("--backup-dir")
    p.add_argument("--delete-b5", action="store_true")
    p.add_argument("paths", nargs="+")
    p.set_defaults(fn=cmd_set)
    p = sub.add_parser("classify")
    p.add_argument("--mods", required=True)
    p.add_argument("subtypes", nargs="+")
    p.set_defaults(fn=cmd_classify)
    p = sub.add_parser("audit")
    p.add_argument("--mods", required=True)
    p.add_argument("--exclude", action="append", default=[], help="prefab file-name glob to skip, e.g. 'NW* *.sbc'")
    p.add_argument("paths", nargs="+")
    p.set_defaults(fn=cmd_audit)
    a = ap.parse_args()
    return a.fn(a)


if __name__ == "__main__":
    sys.exit(main())
