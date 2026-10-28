#!/usr/bin/env python3
"""
save_relations.py - show the faction relations and reputations stored in a world save.

Why: up to MES 2.75.02, MES and turrets read different data. Turrets (vanilla and WeaponCore) use the faction-to-faction relation
between two NPC factions; MES (up to 2.75.02) rated an NPC-vs-NPC target from the target owner identity's own reputation with
the rating NPC's faction. See references/behaviors_and_autopilot.md (target profiles) and
references/third_party_integrations.md section 1H.

Usage:
  save_relations.py PATH\\TO\\World\\Sandbox.sbc [--tags TAG,TAG,...]

Prints:
  1. Faction <-> faction relations (<MyObjectBuilder_FactionRelation>): what turrets use. Pairs not listed count
     as Enemies for turrets.
  2. Identity -> faction reputation (<MyObjectBuilder_PlayerFactionRelation>), grouped by the identity's own
     faction: what MES used for NPC-vs-NPC up to 2.75.02, and still uses to rate a player. An identity with no entry reads the faction's StartingReputation, or Enemies at the
     economy's ReputationHostileMid (vanilla -1000) if it has none.
The save only changes when the world is saved.
"""
import argparse
import collections
import re
import sys


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("sandbox")
    ap.add_argument("--tags", help="comma-separated faction tags to show (default: all)")
    a = ap.parse_args()
    t = open(a.sandbox, encoding="utf-8-sig", errors="replace").read()
    want = {s.strip() for s in (a.tags or "").split(",") if s.strip()}

    fac, members = {}, {}
    for m in re.finditer(r"(?s)<MyObjectBuilder_Faction>(.*?)</MyObjectBuilder_Faction>", t):
        b = m.group(1)
        tag = re.search(r"<Tag>([^<]*)</Tag>", b)
        fid = re.search(r"<FactionId>(-?\d+)</FactionId>", b)
        if not (tag and fid):
            continue
        fac[fid.group(1)] = tag.group(1)
        for pid in re.findall(r"<PlayerId>(-?\d+)</PlayerId>", b):
            members[pid] = tag.group(1)
    show = lambda tag: tag is not None and (not want or tag in want)

    print("Faction <-> faction (turrets):")
    for m in re.finditer(r"(?s)<MyObjectBuilder_FactionRelation>(.*?)</MyObjectBuilder_FactionRelation>", t):
        b = m.group(1)
        f1 = fac.get(re.search(r"<FactionId1>(-?\d+)", b).group(1))
        f2 = fac.get(re.search(r"<FactionId2>(-?\d+)", b).group(1))
        if show(f1) and show(f2):
            rel = re.search(r"<Relation>([^<]*)", b)
            rep = re.search(r"<Reputation>(-?\d+)", b)
            print("  %-12s %-12s %-9s %s" % (f1, f2, rel.group(1) if rel else "?", rep.group(1) if rep else "?"))

    print("\nIdentity (grouped by its faction) -> faction reputation (MES for NPC-vs-player, and for NPC-vs-NPC up to 2.75.02; count of identities per value):")
    agg = collections.defaultdict(collections.Counter)
    for m in re.finditer(r"(?s)<MyObjectBuilder_PlayerFactionRelation>(.*?)</MyObjectBuilder_PlayerFactionRelation>", t):
        b = m.group(1)
        who = members.get(re.search(r"<PlayerId>(-?\d+)", b).group(1), "(no faction)")
        f = fac.get(re.search(r"<FactionId>(-?\d+)", b).group(1))
        rep = re.search(r"<Reputation>(-?\d+)", b)
        if show(f) and (show(who) or who == "(no faction)"):
            agg[(who, f)][rep.group(1) if rep else "?"] += 1
    for (who, f), c in sorted(agg.items()):
        print("  %-12s -> %-12s %s" % (who, f, dict(c)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
