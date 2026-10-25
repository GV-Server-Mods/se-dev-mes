---
name: se-dev-mes
description: >-
  Use this skill when creating, editing, testing in game, diagnosing, or troubleshooting Space Engineers
  Modular Encounters Systems (MES) and RivalAI encounters, spawn groups, behaviors,
  autopilot profiles, triggers, or SBC XML profiles. Authoritative guide covering MES
  Events vs RivalAI Grid Triggers, 1,866 source-extracted tags, boolean master gates,
  XML deserialization quirks, zero-stripping bugs, spawner setups, sandbox variable persistence,
  economy store grid sales, and verified engine workarounds.
license: MIT
allowed-tools: Read, run_command
---

# SE Dev MES & RivalAI Modding Guide

**Applies to Space Engineers version 1 with Modular Encounters Systems (MES) and RivalAI.** MES/RivalAI architecture, SBC pitfalls, and engineering standards for encounter designers and AI coding agents.

**Claim classification**:
- **[HARD]** = verified in the local MES C# source or enforced by the SE engine. Violations fail deterministically (crash, silent no-op, profile load failure).
- **[SOFT]** = field-tested on a live server, not pinned to a code path. An MES or SE update can invalidate it; re-validate if behavior changes.

---

## 1. Source of Truth & Reference Library

> [!IMPORTANT]
> **The MES C# source is the sole source of truth.** Online wikis and guides are often outdated or wrong. This skill (1,866 tags across 41 profile types, checked against that source) overrides generic MES overviews: never use Godimas101's `se-frameworks/references/mes.md`.

### A. Companion Skills
C# ModAPI, decompiled engine code, Torch and PB scripts: [CometWorks skills](https://github.com/CometWorks/skills) (`se-dev-game-code`, `se-dev-server-code`, `se-dev-mod`, `se-dev-torch`); `.mwm` models and TextSurfaceScripts: [Godimas101's se-claude-skill](https://github.com/Godimas101/se-claude-skill) (`se-assets`, `se-tss`; not its `mes.md`).

### B. Reference Library (Progressive Disclosure)
Detail lives in `references/`; open the file for the topic at hand. Keep this file a lean router: harnesses cap SKILL.md at **5,000 tokens** and silently truncate past it (`Update-MesSkill.ps1` checks).

| Reference Document | Key Topics Covered |
| :--- | :--- |
| [tag_recipes.md](references/tag_recipes.md) | **Start here when writing profiles.** Audited tag groups per feature (RivalAI attach, chat + sound, banks, reinforcements, counters, health, autopilot, despawn, zones, debounce, weapons, loot, commands). |
| [profiles_and_tags.md](references/profiles_and_tags.md) | Catalog of 30+ profile types, Registration Phases 1–5, tag types, token scope/rules, and the string-Tag broadcast system. |
| [spawning_and_conditions.md](references/spawning_and_conditions.md) | Spawners, environment gates, threat scoring, altitude formulas, and event spawners. |
| [behaviors_and_autopilot.md](references/behaviors_and_autopilot.md) | 11 Behavior subclasses, Role vs. CombatType state machines, autopilot profiles, command networks (parent/child, escort filters), `DespawnMES` triggers. |
| [dialogue_and_chat.md](references/dialogue_and_chat.md) | Dialogue banks, the shared bank chat profile, chance rolls, chat tokens and range, target-state trigger patterns for chatter. |
| [aircraft_behaviors_and_tuning.md](references/aircraft_behaviors_and_tuning.md) | Attack-run tuning, profile-swap triggers, fixed-gun gates, WeaponCore shoot mode (why MES fixed guns never fire), hover fighters, tuning method. |
| [manipulation_and_dereliction.md](references/manipulation_and_dereliction.md) | Block replacements, weapon randomizer (`<Public>true</Public>`), dereliction, AiEnabled bots, and ContainerTypes loot tables. |
| [events_and_zones.md](references/events_and_zones.md) | MES Events vs RivalAI Triggers, boolean master gates, zero-stripping bug, dynamic zones, Event Templates & TemplateGroups (lifecycle, limits, Missions), contract-block pairing. |
| [economy_and_stores.md](references/economy_and_stores.md) | Store grid sales (MES store items + `[MES Store]`), purchase spawn placement, icons, automated store refresh. |
| [third_party_integrations.md](references/third_party_integrations.md) | WeaponCore (800m clamp, range desync, lead prediction, NPC handicaps, flares, weapon setup matrix), Defense Shields, AiEnabled, Water Mod. |
| [diagnostics_and_troubleshooting.md](references/diagnostics_and_troubleshooting.md) | In-game admin commands, log error signatures, sim-speed optimization, anti-clang mitigations. |
| [testing_and_debugging.md](references/testing_and_debugging.md) | Writing in-game test procedures: spawning test NPCs by spawn type, visual checks, debug messages, log triage, instrumenting local MES. |
| [sbc_xml_editing_guide.md](references/sbc_xml_editing_guide.md) | IDE setup (`*.sbc -> xml`), `<Description>` protection, encoding rules, safe formatting. |

### C. Production-Tested Examples
Annotated `.sbc` implementations based on real workshop mods:
- [role_combattype_state_machine.sbc](examples/role_combattype_state_machine.sbc): Role + CombatType state machine.
- [courier_logistics_network.sbc](examples/courier_logistics_network.sbc): Parent-child courier logistics network.
- [planetary_convoy_escort.sbc](examples/planetary_convoy_escort.sbc): Planetary convoy with event spawning and escorts.
- [automated_economy_store.sbc](examples/automated_economy_store.sbc): Automated store inventory refresh loop.
- [merchant_safezone_station.sbc](examples/merchant_safezone_station.sbc): Safezone station (`[CreateSafeZone:true]`) + wandering merchant.

---

## 2. MES Architecture & Core Mental Models

- **Events vs. Triggers**: MES Events run globally (`EventManager`, no grid needed); RivalAI Triggers run per grid on its Remote Control. **They use different tag names** (`[Spawner:]` vs `[SpawnData:]`, singular vs plural zone lists): Tag-Name Matrix in [`events_and_zones.md`](references/events_and_zones.md) §1.A.
- **ContainerTypes & Loot**: paired list counts **must match 1:1** or MES drops every assignment. → [`manipulation_and_dereliction.md`](references/manipulation_and_dereliction.md) §6

---

## 3. SBC XML Deserialization Quirks

> [!CAUTION]
> **Hard Rules (`audit_sbc.ps1` enforces them)**:
> 1. **One `<SubtypeId>` per `<Id>`**: extras are discarded and the profile fails to load.
> 2. **One `<Id>` per `<Prefab>`**: duplicates register the prefab under the wrong Subtype.
> 3. **`[//Comment]` inside `<Description>`, never `<!-- -->`**: an XML comment there aborts loading the whole mod.
> 4. **UTF-8 only**: UTF-16 or legacy-codepage files fail the deserializer.
> 5. **No empty `.sbc` files**: `Root element is missing` stops the whole world loading.

Formatting rules and snippet tooling: [`sbc_xml_editing_guide.md`](references/sbc_xml_editing_guide.md).

---

## 4. Boolean Master Gates (Events and RivalAI Actions)

> [!CAUTION]
> **[HARD]** A child tag runs only when its gate is `true`, in `[MES Event Action]` and `[RivalAI Action]` alike: `[ChangeCounters:true]` + `[SetCounters:]`, `[SpawnEncounter:true]` + `[SpawnData:]`/`[Spawner:]`, `[UseChatBroadcast:true]` + `[ChatData:]`, `[ChangeAutopilotProfile:true]` + `[AutopilotProfile:]`. Triggers, chats and spawns need `[UseTrigger:true]`/`[UseChat:true]`/`[UseSpawn:true]` (conditions default to on).

Gate tables: [`events_and_zones.md`](references/events_and_zones.md) §2; RivalAI action tags: [`profiles_and_tags.md`](references/profiles_and_tags.md) §2C.

---

## 5. The Zero-Stripping Bug (`TagParse.cs`)

**[HARD]** Integer-list parsers strip `0` values: `[CustomCountersTargets:0]` becomes an empty list (`Counter Names and Targets List Counts Don't Match`). Use `-1` with `[CounterCompareTypes:LessOrEqual]` / `[Greater]`. Affected tags: [`events_and_zones.md`](references/events_and_zones.md) §3.

---

## 6. Token Matrix & Scope (`IdsReplacer.cs`)

**[HARD]** `{Faction}`, `{SpawnGroupName}`, `{Position}` and custom tokens resolve **only in RivalAI Triggers**; Event chat replaces only `{PlayerName}`/`{GPS}` (exception: an Event `[SpawnEncounter:true]` replaces `{Faction}` in the `[SpawnData:]` spawner's `[SpawnGroups:]`, from `[SpawnFactionTags:]`). Tokens in profile names (`[Actions:]`, `[Triggers:]`) **never resolve**. The separate string-**Tag** broadcast (`[Tags:]` + `[EnableTriggerTags:]`, `[ToggleEventTags:]`, ...) reaches every Trigger or Event with that tag; Trigger and Event tags are separate pools. → [`profiles_and_tags.md`](references/profiles_and_tags.md) §5-6

---

## 7. Verified Engine Pitfalls & Workarounds

Each is **[HARD]** unless marked; detail behind the arrow.

- **Weapons**: turret ranges clamp to 800 m on spawn (`[SetWeaponsToMaxRange:true]`); WeaponCore fixed guns on "Auto (AI Controlled)" ignore MES, so save them on **Mouse Control** (`wc_shootmode.py`); `[UseAntiSmartWeapons]` sees only WC1 `AntiSmart` flares. → [`third_party_integrations.md`](references/third_party_integrations.md) §1
- **Relations**: MES rates NPC-vs-NPC from the target owner's own reputation (none stored: `StartingReputation`, else Enemy), and 500 is Neutral to MES, Friendly in vanilla; turrets use the faction-to-faction relation (unset = Enemies). Forced targets use `[OverrideTargetData:]` (default Enemy-only). → [`behaviors_and_autopilot.md`](references/behaviors_and_autopilot.md) target profiles, [`third_party_integrations.md`](references/third_party_integrations.md) §1H
- **Stores** sell prefabs from the MES store-items file (quantity 1); `GridsForSale` is only for Keen stations. → [`economy_and_stores.md`](references/economy_and_stores.md)
- **`[Type:WaypointNear]`/`WaypointFar` off a CargoShip stalls every NPC's AI**; use `BehaviorTriggerA` or `Position`. → [`diagnostics_and_troubleshooting.md`](references/diagnostics_and_troubleshooting.md) §4.4
- **Zones** match `[PublicName:]`, never `[Name:]`; use `InsideActiveZone` (`InsideZone` is true for inactive zones). → [`events_and_zones.md`](references/events_and_zones.md) §4
- **Manipulation**: dereliction needs `[UseGridDereliction:true]` + a `[Blocks:]` list, and its percentages `[UseSeparatePercentages:true]`; the weapon randomizer skips definitions without `<Public>true</Public>`. → [`manipulation_and_dereliction.md`](references/manipulation_and_dereliction.md) §2-3
- **A misspelled faction tag** drops the spawn group to 0% (`Could Not Get Valid NPC Faction`). → [`spawning_and_conditions.md`](references/spawning_and_conditions.md) §6
- **Waypoints, commands, timers**: `RelativeRandom` follows the grid (use `EntityRandom`); random waypoints ignore water; replies beat `EnableTriggers`; `CommandFromParent` matches only the real parent from 2.75.00; cooldowns re-roll and persist. → [`behaviors_and_autopilot.md`](references/behaviors_and_autopilot.md) §5, §7, §8
- **Weak gyro turning (rovers included)**: Keen's gyro ramp cuts the push to ~1/8 when a request is far from the current rate, and MES rewrites it every 0.25 s, so more gyros or bigger multipliers barely help. Put `[UseAircraftFlightModel:true]` + `[MaxRotationStep:0.5]` + `[LimitRotationSpeed:false]` on any gyro-steered NPC and set `MaxRotationMagnitude` to a rate it can stop from. → [`behaviors_and_autopilot.md`](references/behaviors_and_autopilot.md) §3G
- **`MaxVelocityAngleForSpeedControl`**: the default 5 overshoots moving waypoints. **180** on MES 2.75.00+ (field-tested); 90 at most before. → [`aircraft_behaviors_and_tuning.md`](references/aircraft_behaviors_and_tuning.md) §1
- **Target triggers** (2.75.02+): `TargetFar` + `[AllowTargetFarWithoutTarget:true]` fires once the target is gone, and every `LostTarget` trigger sees the edge; on older builds use a `NoTarget` timer. → [`aircraft_behaviors_and_tuning.md`](references/aircraft_behaviors_and_tuning.md) §2
- **Escorts**: up to 2.75.01 a slot is never freed while the escort lives (2.75.02+: dead escorts are cleaned up, `[LeaveEscortSlot:true]` frees one); a refused request gets no reply; Escort Retreat is one-way. → [`behaviors_and_autopilot.md`](references/behaviors_and_autopilot.md) §3D
- **Dialogue banks**: a bank's chat profile is ONE object shared by every grid on it, chosen per behavior, never per `{Faction}`. → [`dialogue_and_chat.md`](references/dialogue_and_chat.md)
- **Despawn**: `[Type:DespawnMES]` needs `[DespawnTypeFromSpawner:Any]`; ships of 12+ grids only partly despawn (MES #412). → [`behaviors_and_autopilot.md`](references/behaviors_and_autopilot.md) §9, [`diagnostics_and_troubleshooting.md`](references/diagnostics_and_troubleshooting.md) §4.17
- **Contracts**: `[ContractBlocks:]`/`[ContractBlockProfiles:]` pair by index; template event instances are never removed automatically. → [`events_and_zones.md`](references/events_and_zones.md) §5D-F
- **Silently ignored**: a spawn group without the `[Modular Encounters SpawnGroup]` header; `[RivalAI Target]` without `[UseCustomTargeting:true]`; inline spawn conditions next to `[SpawnConditionsProfiles:]` (and the reverse for statics: a Description with `[StaticEncounter:true]` hides the referenced profile); `[Type:Damage]` without `[DamageTypes:Any]`; `[Triggers:A,B]` (one name per tag). `[Type:HealthPercentage]` fires at or *above* the threshold. → [`spawning_and_conditions.md`](references/spawning_and_conditions.md) §2, [`behaviors_and_autopilot.md`](references/behaviors_and_autopilot.md) §4
- **[SOFT]** Force-despawn disabled aircraft to avoid falling-airframe Havok loops. → [`diagnostics_and_troubleshooting.md`](references/diagnostics_and_troubleshooting.md) §5

---

## 8. Tooling & Diagnostics

### A. Skill Scripts
The scripts live in the skill, never in the mod: run them from the skill root as `uv run scripts/<name>.py` or `powershell -ExecutionPolicy Bypass -File scripts/<name>.ps1` (audits take `-Path <mod Data dir>`); a mod project may have a `run-mes-audit.ps1 -Audit sbc|tags|refs|prefabs|unknown|wc` shim.

**Before MES work, run `check_mes_sync.py`**: it compares the tag cache with the installed MES source (`%AppData%\SpaceEngineers\Mods\Modular-Encounters-Systems`) and lists newer MES commits. On drift, `Update-MesSkill.ps1` rebuilds the cache and re-runs the audits.

| Tool | Purpose |
| :--- | :--- |
| `query_mes_tags.py` | Tag, data type and master-gate lookup (`--tag Zone`) |
| `audit_unknown_tags.py` | Tags, headers and trigger types MES does not parse |
| `audit_sbc.ps1` | Deserializer hazards (§3) |
| `audit_mes_tags.ps1` | Master gates, zero-stripping, factions, dead triggers |
| `audit_mes_references.ps1` | Cross-file profile references, RivalAI remote setup (WARN only; vanilla remotes stay legal) (`-WarnOrphans -SkipPrefabs`) |
| `audit_prefabs.ps1` | Prefab SubtypeId vs file name, 12+ grids, stale `.sbcB5` (`-CleanStaleB5`) |
| `audit_prefab_thrust.py` | Thruster directions per NPC prefab vs its behavior (`--path <Data>/Prefabs`) |
| `test_tag_recipes.py` | Builds every recipe and runs the audits on it; run after editing `tag_recipes.md` |
| `wc_shootmode.py` | WeaponCore shoot mode: `list`/`classify`/`audit`, set Mouse Control; `neutrals` lists/sets the Neutrals override |
| `save_relations.py` | Faction and identity reputations in a save's `Sandbox.sbc` (turret vs MES relations) |
| `Format-MesSbc.ps1`, `Add-MesProfileSnippet.ps1` | Formatting and `EntityComponent` injection that protect `<Description>` |
| `New-MesProfile.ps1` | Scaffolds (`-Pattern -ModPrefix -Name -Faction`): `DefendedWreck`, `ConvoyLeaderEscort`, `DynamicZoneLadder`, `StoreGrid`, `DynamicStateNpc`, `PlanetaryInstallation`, `CombatDrone`, `ReinforcementNetwork`, `BossEncounter` |

### B. In-Game Testing & Troubleshooting
**Write every test procedure per [`testing_and_debugging.md`](references/testing_and_debugging.md)**: spawn the NPC with `/MES.Spawn.<Type>.<SpawnGroup>` (its conditions need that spawn type; never paste a blueprint), check visually first (`/MES.IGGB`, `/MES.Debug.DrawPaths`, `/MES.Debug.ShowAllZones`), then `[DebugMessage:]`, then logs (`/MES.BehaviorDebug.Trigger.true`, copied with `/MES.IGLBD.Trigger`; the type is required), and only last debug lines in the local MES copy. Every step and check must be something a player can do and see. `[DebugMessage:]` and the event debug tags are development-only. Commands and log signatures: [`diagnostics_and_troubleshooting.md`](references/diagnostics_and_troubleshooting.md) §2, §4.
