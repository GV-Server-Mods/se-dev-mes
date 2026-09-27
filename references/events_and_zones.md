# MES Events, Zones & Sandbox Persistence Reference

Architectural reference covering global MES Events, dynamic spherical/box zones, boolean master gates, and session sandbox variable persistence.

---

## 1. MES Event System Architecture

Unlike RivalAI Triggers which run locally on in-world grids via Remote Control blocks, **MES Events** run globally at the session level via `EventManager`:
- **Server-Authoritative**: Runs exclusively on dedicated servers and host machines (`IsServer`).
- **No Grid Required**: Executes even when no NPC grids exist in the world.
- **Global Coordination**: Manages server-wide progression, zone radius expansions, territory ladders, weekly schedules, and scripted campaign encounters.

### A. Tag-Name Matrix: RivalAI Grid Triggers vs. MES Event Actions
MES Events and RivalAI Grid Triggers use **different tag names** for sub-profiles and lists. Using the wrong variant silently fails:

| Feature | RivalAI Grid Action Tag | MES Event Action Tag | Notes |
| :--- | :--- | :--- | :--- |
| **Encounter Spawner** | `[Spawner:ProfileId]` | `[SpawnData:ProfileId]` | Using `[Spawner:]` in an Event Action causes silent failure (`Spawner.Count == 0`). |
| **Chat Message** | `[UseChatBroadcast:true]` + `[ChatData:ProfileId]` | `[UseChatBroadcast:true]` + `[ChatData:ProfileId]` | Same tag on both sides (`ActionProfile.cs:73`, `EventActionProfile.cs:73`). There is no `[Chat:]` tag anywhere. |
| **Counter Changes** | `[IncreaseSandboxCounters:Name]` | `[ChangeCounters:true]` + `[IncreaseCounters:Name]` | MES Event Actions **require** `[ChangeCounters:true]` gating. |
| **Zone Resizing** | `[ChangeZoneAtPosition:true]` (grid inside the zone) or `[ChangeZoneOnlyByName:true]` (any distance, 2.74.00) + `[ZoneName:]` + `[ZoneRadiusChangeType:]` + `[ZoneRadiusChangeAmount:]` | `[ChangeZoneByName:true]` + `[ZoneNames:]` + `[ZoneRadiusChangeTypes:]` + `[ZoneRadiusChangeAmounts:]` (2.74.00) | RivalAI actions use **singular** tag names and have no `ChangeZoneByName`; MES Event Actions use **plural lists**. `ActionSystem.cs:1916` runs the RivalAI zone block only when one of the two RivalAI gates is true. |

---

## 2. Boolean Master-Gate Protocol (MES Events Only)

> [!CAUTION]
> **The Golden Rule**: Sub-configuration tags inside `[MES Event Action]` and `[MES Event Condition]` **do nothing on their own**. They are guarded by boolean master gates that default to `false`.
> Omitting the master gate causes **silent failure**: MES logs no errors, but skips the action entirely.

### A. MES Event Action Master Gates (`EventActionExecution.cs`)

| Master Gating Tag (Required) | Dependent Child Tags Enabled | Purpose / Effect |
| :--- | :--- | :--- |
| `[ChangeCounters:true]` | `[SetCounters:]`, `[SetCountersAmount:]`, `[IncreaseCounters:]`, `[IncreaseCountersAmount:]`, `[DecreaseCounters:]`, `[DecreaseCountersAmount:]` | Mutating Sandbox integer counters. |
| `[ChangeBooleans:true]` | `[SetBooleansTrue:]`, `[SetBooleansFalse:]` | Setting Sandbox boolean variables. |
| `[SpawnEncounter:true]` | `[SpawnCoords:]`, `[SpawnFactionTags:]`, `[SpawnData:]`, `[SpawnReplaceKeys:]`, `[SpawnReplaceValues:]` | Spawning encounters via event actions. **[HARD]** `{Faction}` inside a `[SpawnData:]` value *does* resolve here — a bespoke, index-aligned `{Faction}` → `[SpawnFactionTags:]` replace, not `IdsReplacer` (which never runs in Events). This is the one token exception inside MES Events besides sandbox vars and chat `{PlayerName}`. See [`references/profiles_and_tags.md`](references/profiles_and_tags.md) §5 Rule 1. |
| `[ChangeZoneByName:true]` | `[ZoneNames:]`, `[ZoneRadiusChangeTypes:]`, `[ZoneRadiusChangeAmounts:]` | Dynamically modifying spherical zones by name (`PublicName`, §4 rule 2; `Persistent` zones only). **[HARD]** Change types are `ModifierEnum`: `Set`, `Add`, `Subtract`, `Multiply`, `Divide`. `Increase`/`Decrease` fail to parse, the entry is dropped, and the index-aligned change is silently skipped. Same values for the RivalAI `[ZoneRadiusChangeType:]`. |
| `[ChangeZoneAtPosition:true]` | `[ZoneCoords:]`, `[ZoneToggleActiveModes:]` | Activating/deactivating zones at coordinates. |
| `[ToggleEvents:true]` | `[ToggleEventIds:]`, `[ToggleEventIdModes:]`, `[ToggleEventTags:]`, `[ToggleEventTagModes:]` | Enabling or disabling other MES Events. **[HARD]** These same four tags also exist on `[RivalAI Action]`/`[MES AI Action]` (a different C# class, `ActionReferenceProfile.cs`). On that side they token-resolve via `IdsReplacer`; here, in `[MES Event Action]`, they don't — `EventActionExecution.cs` never wraps them. Full rundown: [`references/profiles_and_tags.md`](references/profiles_and_tags.md) §6C. |
| `[ResetCooldownTimeOfEvents:true]` | `[ResetEventCooldownIds:]`, `[ResetEventCooldownTags:]` | Forcing events back to 0 or full cooldown. Same RivalAI-vs-Event dual-declaration/token-asymmetry as `[ToggleEvents:]` above — see [`references/profiles_and_tags.md`](references/profiles_and_tags.md) §6C. |
| `[UseChatBroadcast:true]` | `[ChatData:]`, `[UseChatOverrideAuthor:true]`, `[ChatOverrideAuthor:]`, `[UseChatOverrideMessage:true]` | Transmitting HUD / chat notifications. |
| `[SetSandboxStrings:true]` *(2.74.00)* | `[SandboxStrings:name,value]` | Sets sandbox string variables (sandbox-var tokens resolve in name and value). **[HARD]** An entry with an empty name or value hits a `return` inside the loop (`EventActionExecution.cs:119`), which aborts **every later step of this action**, not just that entry. |
| `[SetSandboxVector3Ds:true]` *(2.74.00)* | `[SandboxVector3Ds:name,{X:0 Y:0 Z:0}]` | Sets sandbox Vector3D variables. |
| `[AddInstanceEventGroup:true]` | `[InstanceEventGroupId:]`, `[InstanceEventGroupReplaceKeys:]`, `[InstanceEventGroupReplaceValues:]` | Instantiates a `[MES Event TemplateGroup]` (§5). |
| `[TryContractSuccess:true]` / `[TryContractFail:true]` | *(none)* | Finish/fail the MES mission contract whose id seeded this event instance. **[HARD]** A `[MES Mission]`'s `[EventConditionIds:]` (with `[UseAnyPassingEventCondition:]`) were never read before MES 2.74.04 (`Mission.cs` looped `PlayerConditionIds` instead), so only `[PersistantEventConditionIds:]` gated missions on older builds. |
| `[AddGPSToPlayers:true]` | `[GPSNames:]`, `[GPSDescriptions:]`, `[GPSCoords:]`, `[UseGPSObjective:true]` | Creating HUD GPS waypoints for players. |
| `[RemoveGPSFromPlayers:true]` | `[RemoveGPSNames:]` | Deleting HUD GPS waypoints from players. |
| *None (Self-gated)* | `[DebugChatMessage:<Text>]`, `[DebugHudMessage:<Text>]` | Diagnostic test messages for event development (never use in production). |

### B. MES Event Condition Master Gates (`EventConditions.cs`)

| Master Gating Tag (Required) | Dependent Child Tags Evaluated | Purpose / Effect |
| :--- | :--- | :--- |
| `[CheckCustomCounters:true]` | `[CustomCounters:]`, `[CustomCountersTargets:]`, `[CounterCompareTypes:]` | Evaluating sandbox counter variables. |
| `[CheckTrueBooleans:true]` | `[TrueBooleans:]`, `[AllowAnyTrueBoolean:true/false]` | Requiring sandbox booleans to be true. |
| `[CheckFalseBooleans:true]` | `[FalseBooleans:]`, `[AllowAnyFalseBoolean:true/false]` | Requiring sandbox booleans to be false. |
| `[CheckPlayerNear:true]` | `[PlayerNearCoords:]`, `[PlayerNearDistanceFromCoords:]`, `[PlayerNearMinDistanceFromCoords:]` | Distance checks from specified coords. |
| `[CheckThreatScore:true]` | `[ThreatScoreAmount:]`, `[ThreatScoreDistance:]`, `[ThreatScoreCoords:]` | Player combat grid threat checks. |
| `[CheckOnSession:true]` *(2.74.00)* | *(none)* | Satisfied exactly once per game load (the first evaluation after load), then fails until the next load (`EventConditions.cs:541`). |

---

## 3. The Zero-Stripping Bug & Workarounds

In `TagParse.cs`, MES strips all `0` values from integer lists unless called with `preserveZero: true`:
```csharp
if (!preserveZero)
    result.RemoveAll(item => item == 0);
```

- **[HARD] Affected Tags**:
  - `CustomCountersTargets` in `EventConditions.cs`
  - `CustomSandboxCountersTargets` in `ConditionReferenceProfile.cs`
  - `CustomSandboxCountersTargets` in `SpawnConditionsProfile.cs`
  - `CustomZoneCounterValue` in `ZoneConditionsProfile.cs`
  - `IncreaseCountersAmount` / `DecreaseCountersAmount` in `EventActionReference.cs`
- **Symptom**: Using `[CustomCountersTargets:0]` strips the `0`, resulting in an empty list. Evaluation fails with `Counter Names and Targets List Counts Don't Match`.
- **Workaround**:
  - To test `< 0` (e.g. floor clamp): Use `[CustomCountersTargets:-1]` with `[CounterCompareTypes:LessOrEqual]`.
  - To test `>= 0` (e.g. positive gate): Use `[CustomCountersTargets:-1]` with `[CounterCompareTypes:Greater]`.

---

## 4. Dynamic Zones & Progression Ladders (`[MES Zone]`)

Zones define spatial volumes that enforce territory rules, modify spawn pools, and track localized counters:

```xml
<EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
  <Id>
    <TypeId>Inventory</TypeId>
    <SubtypeId>ModPrefix-Zone-TerritoryAlpha</SubtypeId>
  </Id>
  <Description>
    [MES Zone]
    [Name:ModPrefix_Zone_Alpha]
    [PublicName:Contested Territory Alpha]
    [Active:true]
    [Persistent:true]
    [Coordinates:{X:62495 Y:28019 Z:37195}]
    [Radius:25000]
  </Description>
</EntityComponent>
```

### Critical Zone Rules & Quirks:
1. **[HARD] `[Type:InsideZone]` vs `[Type:InsideActiveZone]`**:
   - `[Type:InsideZone]` calls `ZoneManager.InsideZoneWithName(..., onlyActive: false)`. It evaluates `true` even when the target zone is deactivated!
   - Always use `[Type:InsideActiveZone]` and `[Type:OutsideActiveZone]`.
2. **[HARD] Zones are looked up by `[PublicName:]`, not `[Name:]`**: every by-name zone lookup compares `zone.PublicName` (`ZoneManager.cs` `InsideZoneWithName`, `ToggleZones`, `ChangeZoneRadius/Counters/Bools`; `SpawnConditions.cs:1926` for Zone Conditions). `[ZoneName:]` (Triggers, RivalAI Actions, Zone Conditions, Player Conditions) and `[ZoneNames:]` (MES Event Actions) must therefore equal the zone's `[PublicName:]`. `[Name:]` is stored but no lookup reads it, and `[ZoneName:]` inside `[MES Zone]` is ignored. `scripts/audit_mes_references.ps1` errors on a reference that matches a zone's `[Name:]` but not its `[PublicName:]`.
3. **Spawn restrictions (overhauled in MES 2.74.00)** — `ZoneManager.GetAllowedSpawns()`, evaluated only for **Active** zones:

   | Restriction | Tags | Applies when | Precedence |
   | :--- | :--- | :--- | :--- |
   | No spawns at all | `[NoSpawnZone:true]` | position inside zone (not gated by `Persistent`) | overrides everything |
   | SpawnGroup whitelist | `[UseAllowedSpawnGroups:true]` + `[AllowedSpawnGroups:]` | see note below | over mod ID and faction |
   | SpawnGroup blacklist | `[UseRestrictedSpawnGroups:true]` + `[RestrictedSpawnGroups:]` | inside zone **and** `[Persistent:true]` | over mod ID and faction |
   | Mod ID white/blacklist | `[UseAllowedModIDs:true]` + `[AllowedModIDs:]` / `[UseRestrictedModIDs:true]` + `[RestrictedModIDs:]` | inside zone **and** `[Persistent:true]` | over faction |
   | Faction white/blacklist | `[UseAllowedFactions:true]` + `[AllowedFactions:]` / `[UseRestrictedFactions:true]` + `[RestrictedFactions:]` | inside zone **and** (`[Persistent:true]` or `[PlayerKnownLocation:true]`) | lowest |

   - **[HARD] `Persistent` still gates most restrictions** (`ZoneManager.cs:287-344`), and `Persistent` defaults to `false`.
   - **[HARD] AllowedSpawnGroups is two rules in one**: with `[UseAllowedSpawnGroups:true]`, every listed SpawnGroup becomes *zone-only* world-wide — it can no longer spawn outside any zone that allows it (`OnlyAllowedZoneSpawns`, collected from every active zone regardless of position). Separately, inside a `Persistent` zone the list restricts spawns to only those groups (collected even without the `Use` gate).
   - The short-lived `[UseLimitedFactions:]` / `[LimitedFactions:]` zone tags from the first 2.74.00 build were renamed to `UseAllowedFactions` / `AllowedFactions` (MES commit e2d53a7) and are no longer parsed.
4. **Multiple spheres per zone** *(2.74.00)*: `[CoordinateRadiusPairs:{X:0 Y:0 Z:0},5000]` (repeatable, one pair per tag) adds extra coordinate/radius spheres to one zone.
5. **Placement & debug helpers**: `/MES.Info.GetLocationMatrix` *(2.74.03)* copies your position/orientation to the clipboard for zone setup; `/MES.Debug.ShowZone.<name>`, `/MES.Debug.HideZone.<name>`, `/MES.Debug.ShowAllZones`, `/MES.Debug.HideAllZones` *(2.74.04)* draw zone spheres in-world (`<name>` is the `PublicName` or zone profile SubtypeId).
6. **[HARD] Zone custom bools/counters (RivalAI Action only; broken before MES 2.74.04)**: gate `[ChangeZoneAtPosition:true]` (grid must be inside the zone) or `[ChangeZoneOnlyByName:true]` (any distance), then `[ZoneCustomBoolChange:true]` + `[ZoneCustomBoolChangeName:]` + `[ZoneCustomBoolChangeValue:]`, and/or `[ZoneCustomCounterChange:true]` + `[ZoneCustomCounterChangeName:]` + `[ZoneCustomCounterChangeAmount:]` + `[ZoneCustomCounterChangeType:Set|Add|Subtract|Multiply|Divide]`, with `[ZoneName:<PublicName>]`. Read back with `[MES Zone Conditions]` `[CheckCustomZoneBools:true]` / `[CheckCustomZoneCounters:true]`.
   - Up to 2.74.03 these actions **did nothing**: `MathTools.LowestCount` always returned `0`, so no value was ever written (also affected the KPL variants below); the `...UseKPL` routing was inverted, and the at-position check skipped zones the grid was *inside*. All fixed in 2.74.04 (MES PR #374).
   - Only `[Persistent:true]` zones are changed, matched by `PublicName` (rule 2).
   - Name/amount/type lists are index-aligned; MES uses the **shortest** list and silently drops extra entries. `ZoneCustomCounterChangeAmount` and `ZoneCustomCounterChangeType` take **one value per tag line** (no comma lists; `[ZoneCustomCounterChangeAmount:5,10]` fails to parse and adds nothing). Names and bool values accept comma lists.
   - `[CheckCustomZoneBools:true]` **fails when the bool was never set** on that zone, even when you check for `false`. Set it explicitly first.
7. **[HARD] Known Player Locations (KPLs)**: temporary zones created by `[CreateKnownPlayerArea:true]` (RivalAI Action, at the NPC's position, owned by the NPC's faction), the `/MES.Debug.CreateKPL.<Faction>.<Radius>.<Minutes>` admin command (duration defaults to 30), or the MES API. `[KnownPlayerAreaRadius:]`, `[KnownPlayerAreaTimer:]` (minutes, or `Day`), `[KnownPlayerAreaMaxSpawns:]`. Target KPL variables with `[ZoneCustomBoolChangeUseKPL:true]` / `[ZoneCustomCounterChangeUseKPL:true]` (matches KPLs of the NPC's own faction; `ZoneName` is not used).
   - **Timer must be > 0** *(2.74.04)*: `[KnownPlayerAreaTimer:]` defaults to `30`; a value of `0` or less now **creates no KPL** (logged under `/MES.SpawnDebug.Zone`: `KnownPlayerLocation Not Created At ...: Duration Must Be Greater Than 0`). Before 2.74.04, `-1` created a KPL with no timer. There is no longer a non-expiring KPL. Player presence inside the KPL resets its timer.
   - **KPLs now survive a server restart** *(2.74.04)*. Before, the startup zone validation deleted every KPL (they have no zone profile), so all KPLs vanished on each load.
   - Overlapping KPLs of the same faction merge into one. Since 2.74.04 the merged KPL keeps both zones' bools (OR) and counters (summed); before, the old values were lost.

---

## 5. MES Event Templates & Instance Event Groups

Templates let one set of event profiles be **stamped out as independent live event instances at runtime**, each with its own replaced values (target coordinates, faction, names). This is how MES missions and multi-stage scripted encounters spawn per-instance event chains. It is **not** a random-selection pool.

### A. Profile Types (verified: `ProfileManager.cs`, `TemplateEventGroup.cs`, `Event.cs`)

| Header | Stored as | Role |
| :--- | :--- | :--- |
| `[MES Event Template]` | raw Description text (`TemplateEventProfiles`) | A full `[MES Event]` profile (cooldowns, `[ConditionIds:]`, `[ActionIds:]`, ...) whose text is token-replaced per instance. |
| `[MES Event Condition Template]` | raw text (`TemplateEventConditions`) | An `[MES Event Condition]` resolved and token-replaced per instance. |
| `[MES Event Action Template]` | raw text (`TemplateEventActionProfiles`) | An `[MES Event Action]` resolved and token-replaced per instance. Same master gates as §2.A. |
| `[MES Event TemplateGroup]` | `TemplateEventGroup` | Lists event templates with `[TemplateEventIds:<SubtypeId>]`, **one per tag line** (parsed with `TagStringCheck`, so a comma list becomes one bad id). |

### B. Instantiation
- **Trigger it** with `[AddInstanceEventGroup:true]` + `[InstanceEventGroupId:<TemplateGroup SubtypeId>]` + `[InstanceEventGroupReplaceKeys:{Key1},{Key2}]` + `[InstanceEventGroupReplaceValues:v1,v2]` on a `[MES Event Action]` or a RivalAI Action (RivalAI resolves its own tokens in the values first), or through a `[MES Mission]`'s `[InstanceEventGroupId:]`.
- **[HARD] Every template in the group is instantiated**, not one at random (`AddEventsAsInsertible` loops all `EventIds`). Each becomes an `Event` with SubtypeId `<template>@<InstanceId>`; unknown template ids are skipped silently.
- **[HARD] Token replacement**: the template text, and every condition/action template it references by `[ConditionIds:]`/`[PersistantConditionIds:]`/`[ActionIds:]`, is run through `IdsReplacer.ReplaceText()` with the replace keys plus an automatic `{InstanceId}` (game-time ticks, or the mission's id). Referenced ids that are **not** templates fall back to the normal shared `[MES Event Condition]`/`[MES Event Action]` profiles, un-replaced.
- Lookup of the group happens when the action runs, so load order between these profiles does not matter.
- Instanced events are saved with the world (`Event.Insertable`, `ReplaceKeys`/`ReplaceValues` are ProtoMembers).

### C. Minimal Example

```xml
<!-- Instantiates the group (referenced from an [MES Event] via [ActionIds:]) -->
<EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
  <Id><TypeId>Inventory</TypeId><SubtypeId>GVK-EventAction-StartRaid</SubtypeId></Id>
  <Description>
    [MES Event Action]
    [AddInstanceEventGroup:true]
    [InstanceEventGroupId:GVK-TemplateGroup-Raid]
    [InstanceEventGroupReplaceKeys:{RaidSpawn}]
    [InstanceEventGroupReplaceValues:GVK-Spawn-ScoutRaid]
  </Description>
</EntityComponent>

<!-- The group: one [TemplateEventIds:] line per event template -->
<EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
  <Id><TypeId>Inventory</TypeId><SubtypeId>GVK-TemplateGroup-Raid</SubtypeId></Id>
  <Description>
    [MES Event TemplateGroup]
    [TemplateEventIds:GVK-EventTemplate-Raid]
  </Description>
</EntityComponent>

<!-- The event template: a normal [MES Event] body, token-replaced per instance -->
<EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
  <Id><TypeId>Inventory</TypeId><SubtypeId>GVK-EventTemplate-Raid</SubtypeId></Id>
  <Description>
    [MES Event Template]
    [UseEvent:true]
    [UniqueEvent:true]
    [MinCooldownMs:60000]
    [MaxCooldownMs:60000]
    [ActionIds:GVK-EventActionTemplate-Raid]
  </Description>
</EntityComponent>

<!-- The action template: {RaidSpawn} is replaced for this instance -->
<EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
  <Id><TypeId>Inventory</TypeId><SubtypeId>GVK-EventActionTemplate-Raid</SubtypeId></Id>
  <Description>
    [MES Event Action Template]
    [SpawnEncounter:true]
    [SpawnData:{RaidSpawn}]
    [SpawnCoords:{X:0 Y:0 Z:0}]
    [SpawnFactionTags:SPRT]
  </Description>
</EntityComponent>
```

### D. Contract Blocks (RivalAI Action)
- **[HARD]** `[ApplyContractProfiles:true]` + `[ContractBlocks:<block CustomName>]` + `[ContractBlockProfiles:<[MES Contract Block] SubtypeId>]` exist only on RivalAI Actions. Both are string lists paired **by index** (`ActionSystem.cs` loops to the shorter list), so several boards can be set in one action; each name matches every contract block on the grid with that exact `CustomName`. `[ClearContractContentsFirst:true]` clears the board first.
