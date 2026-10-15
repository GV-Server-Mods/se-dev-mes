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
| `[SpawnEncounter:true]` | `[SpawnCoords:]`, `[SpawnFactionTags:]`, `[SpawnData:]`, `[SpawnReplaceKeys:]`, `[SpawnReplaceValues:]` | Spawning encounters via event actions. **[HARD]** `{Faction}` in the `[SpawnGroups:]` list of the spawner that `[SpawnData:]` names *does* resolve here (not in the `[SpawnData:]` value itself) — a bespoke, index-aligned `{Faction}` → `[SpawnFactionTags:]` replace, not `IdsReplacer`. See [`references/profiles_and_tags.md`](references/profiles_and_tags.md) §5 Rule 1. |
| `[ChangeZoneByName:true]` | `[ZoneNames:]`, `[ZoneRadiusChangeTypes:]`, `[ZoneRadiusChangeAmounts:]` | Dynamically modifying spherical zones by name (`PublicName`, §4 rule 2; `Persistent` zones only). **[HARD]** Change types are `ModifierEnum`: `Set`, `Add`, `Subtract`, `Multiply`, `Divide`. `Increase`/`Decrease` fail to parse, the entry is dropped, and the index-aligned change is silently skipped. Same values for the RivalAI `[ZoneRadiusChangeType:]`. |
| `[ChangeZoneAtPosition:true]` | `[ZoneCoords:]`, `[ZoneToggleActiveModes:]` | Activating/deactivating zones at coordinates. |
| `[ToggleEvents:true]` | `[ToggleEventIds:]`, `[ToggleEventIdModes:]`, `[ToggleEventTags:]`, `[ToggleEventTagModes:]` | Enabling or disabling other MES Events. **[HARD]** These same four tags also exist on `[RivalAI Action]`/`[MES AI Action]` (a different C# class, `ActionReferenceProfile.cs`). On that side they token-resolve via `IdsReplacer`; here, in `[MES Event Action]`, they don't — `EventActionExecution.cs` never wraps them. Full rundown: [`references/profiles_and_tags.md`](references/profiles_and_tags.md) §6C. |
| `[ResetCooldownTimeOfEvents:true]` | `[ResetEventCooldownIds:]`, `[ResetEventCooldownTags:]` | Forcing events back to 0 or full cooldown. Same RivalAI-vs-Event dual-declaration/token-asymmetry as `[ToggleEvents:]` above — see [`references/profiles_and_tags.md`](references/profiles_and_tags.md) §6C. |
| `[UseChatBroadcast:true]` | `[ChatData:]`, `[UseChatOverrideAuthor:true]`, `[ChatOverrideAuthor:]`, `[UseChatOverrideMessage:true]` | Transmitting HUD / chat notifications. |
| `[SetSandboxStrings:true]` *(2.74.00)* | `[SandboxStrings:name,value]` | Sets sandbox string variables (sandbox-var tokens resolve in name and value). **[HARD]** An entry with an empty name or value hits a `return` inside the loop (`EventActionExecution.cs:119`), which aborts **every later step of this action**, not just that entry. |
| `[SetSandboxVector3Ds:true]` *(2.74.00)* | `[SandboxVector3Ds:name,{X:0 Y:0 Z:0}]` | Sets sandbox Vector3D variables. |
| `[AddInstanceEventGroup:true]` | `[InstanceEventGroupId:]`, `[InstanceEventGroupReplaceKeys:]`, `[InstanceEventGroupReplaceValues:]` | Instantiates a `[MES Event TemplateGroup]` (§5). |
| `[RemoveThisInstanceGroup:true]` | *(none)* | Marks every event of this instance (same `InstanceId` tag) for removal; runs last in the action. See §5E. |
| `[TryContractSuccess:true]` / `[TryContractFail:true]` | *(none)* | Finish/fail the MES mission contract whose id seeded this event instance, then remove the instance's events like `[RemoveThisInstanceGroup:true]` (§5E-F). **[HARD]** A `[MES Mission]`'s `[EventConditionIds:]` (with `[UseAnyPassingEventCondition:]`) were never read before MES 2.74.04 (`Mission.cs` looped `PlayerConditionIds` instead), so only `[PersistantEventConditionIds:]` gated missions on older builds. |
| `[AddGPSToPlayers:true]` | `[GPSNames:]`, `[GPSDescriptions:]`, `[GPSCoords:]`, `[GPSColors:]`, `[GPSColorVariables:]`, `[UseGPSObjective:true]` | Creating HUD GPS waypoints for players. **[HARD]** `[GPSDescriptions:]` and `[GPSColors:]` were parsed but never applied before MES 2.74.06 (every GPS got the default description and orange); they now apply per index. `[GPSColors:]` (0-255 per channel) wins; if it is empty or zero for that index, `[GPSColorVariables:name]` reads a sandbox Vector3D of that name (the `{}` are optional). **[HARD] Channel order is `{X:Red Y:Blue Z:Green}`**: both code paths assign `color.B = Y` and `color.G = Z`, so `{X:255 Y:0 Z:128}` is orange (R 255, G 128, B 0), not an RGB-ordered vector (tracking: se-dev-mes#8). Descriptions resolve tokens (`IdsReplacer`; with no NpcData in an Event Action only sandbox variables work). The RivalAI Action version also falls back to the grid's custom Vector3D variables for the color. |
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
   - **Faction lock**: while a player is inside a KPL, only spawn groups of the KPL's faction pass `SpawnConditions.ZoneValidation` there (logged as "not among Allowed Zone Factions"), RivalAI custom spawns (`[SpawnEncounter:true]` Defense waves, helper spawns) included. Overlapping KPLs of different factions allow all of their factions (`ZoneManager.GetAllowedSpawns`). A KPL is always owned by the creating grid's faction; no tag names another faction.
   - **See them**: `/MES.Debug.ShowAllZones` draws a KPL (only one at a time; `diagnostics_and_troubleshooting.md` §2.D).
8. **[HARD] Zones can only be required, never excluded.** `SpawnConditions.ZoneValidation` passes a spawn only when its position is inside an allowed zone; no spawn condition rejects a position for being inside a zone. A zone whitelist also checks where the **player** stands, while planetary installations and drones land kilometres away, so a spawn requested from outside can land inside the zone. To keep encounters out of an area, give their behaviors an `[Type:InsideActiveZone]` trigger for that zone that despawns them.

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
- **[HARD]** `[ApplyContractProfiles:true]` + `[ContractBlocks:<block CustomName>]` + `[ContractBlockProfiles:<[MES Contract Block] SubtypeId>]` exist only on RivalAI Actions. `[ContractProfiles:]` is an alias of `[ContractBlockProfiles:]`.
- **[HARD] Pairing trap**: `[ContractBlocks:]` and `[ContractBlockProfiles:]` are two separate lists **paired by index**, and `ActionSystem.cs` loops only to the **shorter** list. Two `[ContractBlocks:]` lines with one `[ContractBlockProfiles:]` line fill only the first board and nothing is logged. To fill two boards, write two of each in the same order, even when both boards use the same profile:
  ```
  [ApplyContractProfiles:true]
  [ContractBlocks:Contracts North]
  [ContractBlocks:Contracts South]
  [ContractBlockProfiles:ModPrefix-ContractBoard-Escort]
  [ContractBlockProfiles:ModPrefix-ContractBoard-Escort]
  ```
  Both tags drop blank entries at parse time, so an empty slot shifts every later pair; a pair whose profile id isn't registered is skipped (only logged under `/MES.BehaviorDebug.Action.true`: `Couldn't find Mission Profile With Name`).
- **[HARD] Matching**: a name must equal the block's `CustomName` exactly (case-sensitive), and only blocks on the grid that runs the behavior count (`CurrentGrid.Contracts`; not linked subgrids). Each name matches every contract block with that name.
- **[HARD] `[ClearContractContentsFirst:true]` runs per pair** (`ContractBlockProfile.ApplyProfileToBlock` → `InGameContractManager.ClearBlockContracts`) and removes the block's generated, not-yet-accepted contracts. Two pairs that target the same block name therefore clear each other's missions: the second pair wipes what the first just added. Put every mission for one board in one `[MES Contract Block]` profile's `[MissionIds:]` instead.

### E. Relationship Model, Lifecycle & Limits [HARD]
Verified: `Event.cs`, `TemplateEventGroup.cs`, `EventManager.cs`, `EventActionExecution.cs`, `Mission/*.cs`, `IdsReplacer.cs`.

```text
[MES Event]               static: ONE shared Event per profile, created at world load, id = its SubtypeId
[MES Event Template]      stamped: ONE Event per instantiation, id = <template>@<InstanceId>
[MES Event TemplateGroup] bundle: instantiates EVERY listed template in one call, all sharing one InstanceId
   condition/action ids on a stamped event:
     id is a [... Condition Template]/[... Action Template]  -> stamped per instance (<id>@<InstanceId>), text token-replaced
     id is a plain [MES Event Condition]/[MES Event Action]  -> the shared profile, NOT replaced (no tokens resolve)
```

- **Same tags everywhere.** A template is parsed by the same `InitTags` as its non-template twin (`EventProfile`, `EventCondition`, `EventActionReferenceProfile`/`EventActionProfile`), after `string.Replace`. Event-only, template-only and shared tag sets are therefore identical; the only template-specific thing is that `{Key}` text is replaced first. `{Key}` stays literal in non-template profiles. `[MES Event TemplateGroup]` reads only `[TemplateEventIds:]`.
- **Each instance joins the event-tag pool** with its `[Tags:]` plus its `InstanceId` as an extra tag (`Event.Profile`), which is how `RemoveThisInstanceGroup` finds its siblings.
- **Who can start a group**: `[AddInstanceEventGroup:true]` on an `[MES Event Action]`; the same tag on a `[RivalAI Action]` (the values pass through `IdsReplacer` with the Remote Control position, the keys do not); a `[MES Mission]` when its contract is **accepted** (`Contract.TryToActivateCustomContract` → `Mission.Start`, not when the contract is generated); and the `InsertInstanceEventGroup` mod API. An unknown group id silently does nothing.
- **Ids**: `AddEventsAsInsertible` uses `GameDateTime.Ticks` as `{InstanceId}` when no id is passed (event action, RivalAI action, API), one id per call. Two instantiations in the same game tick therefore get the same id: duplicate `<template>@<id>` events that share a tag and are removed together. A `[MES Mission]` passes the Keen contract id instead.
- **Persistence**: instances live in the same `EventsList` and save as `MES-EventsList`, with `Insertable`, `ReplaceKeys`, `ReplaceValues`, `InstanceId`, `TemplateProfileSubtype` and `MarkedforRemoval` stored.
  - On load `Event.Init()` rebuilds each instance from the **current** template text plus the saved keys/values: editing a template changes live instances at the next load (run count and cooldown are kept).
  - Deleting a template leaves its instances in the save, invalid (`ErrorOnSetup`) and silently skipped every pass. The load-time cleanup ("Delete Old Events") skips every `Insertable` event, so nothing ever removes them.
- **Nothing ends an instance by itself.** `[UniqueEvent:true]` only stops further runs; the event stays in the list and the save. Remove one with `[RemoveThisInstanceGroup:true]` or `[TryContractSuccess:true]`/`[TryContractFail:true]` on an `[MES Event Action]` (they run last in the action and mark every event tagged with this `InstanceId` as `MarkedforRemoval`; `EventManager.ProcessEvents` drops them on its next 30-tick pass).
  - **Hazard**: those removal loops read `Event.Profile.Tags` with no null check, and `Profile` is `null` for an orphaned instance, so after a template is deleted they throw on reaching it and the action stops partway. Remove instances before deleting the template. *(Read from source, not reproduced in play; tracking: se-dev-mes#8.)*
- **No instance cap.** Nothing limits how many exist. Every live instance is evaluated on each 30-tick `ProcessEvents` pass, and each stamped action registers `ProfileManager.EventActionReferenceProfiles["<action>@<id>"]`, which is never removed during the session. Long-lived servers should end finished instances.
- **Replace keys** (`IdsReplacer.ReplaceText`): plain `string.Replace` in list order, then the automatic `{InstanceId}` last.
  - A value that contains a later key's text is replaced again (cascade), so keep values free of `{...}` text. A user-supplied `{InstanceId}` key wins, because it runs first.
  - Key and value counts must match. On a mismatch MES shows a "Big error" chat message, copies the text to the clipboard, and **still creates the instance with the unreplaced `{Key}` text**.
  - `[InstanceEventGroupReplaceKeys:]`/`[InstanceEventGroupReplaceValues:]` are comma-split lists with **no escaping**: a comma inside a value splits it and trips the count mismatch. A `[MES Mission]` avoids this: its `[ReplaceKeys:]`/`[ReplaceValues:]` take one entry per tag line and keep commas (`[ReplacePairs:]` is a third form).

### F. `[MES Mission]` vs a Plain `AddInstanceEventGroup` [HARD]
A mission is an instance group plus a Keen custom contract (`MissionProfile.cs`, `Mission.cs`, `InGameContractManager.cs`):
- **Id source**: the Keen contract id becomes `{InstanceId}` (and `{ContractId}`, `MissionType:Custom` only) instead of game-time ticks, so `[TryContractSuccess:true]`/`[TryContractFail:true]` can finish the right contract.
- **Contract type**: `[ContractSubtypeId:]` *(2.74.06 dev, default `MESContract`)* names the `MyObjectBuilder_ContractTypeDefinition` that a `MissionType:Custom` contract uses; before, it was hard-coded. The definition must exist in the game or the contract cannot be created.
- **Timing**: the contract is generated when `[ApplyContractProfiles:true]` stocks the board, and only if `[EventConditionIds:]`/`[PersistantEventConditionIds:]` pass then and the profile's `[ReplaceKeys:]`/`[ReplaceValues:]` counts match. The values go through `IdsReplacer` with the stocking grid's NpcData, so `{Faction}`, `{SpawnGroupName}` and custom strings resolve there. The event group is stamped only when a player **accepts**, after the event conditions are re-checked (`Contract no longer available` if they fail), then `[LeadPlayerConditionIds:]` and `[PlayerConditionIds:]` (a failed player check puts the contract back on the board).
- **Hooks into Keen's contract events**: an instance event tagged `Failed@{InstanceId}` or `Abandoned@{InstanceId}` has its actions run (conditions, cooldown and enabled state are bypassed) when that contract fails or is abandoned. A finished contract pays `[ReputationReward:]` and sets the `[ActivateBooleanNameOnSucces:]` sandbox boolean; an abandoned one charges `[FailReputationPrice:]`.
- **Cleanup is not automatic.** On finish, fail or abandon MES does **not** remove the mission's instance events. The template must end itself with `[RemoveThisInstanceGroup:true]` or `[TryContract*]`; otherwise the events live on in the save.
- **`[Exclusive:true]`**: accepting one contract of the mission removes the mission's other generated contracts on every board, and the mission is not added to a board while one accepted contract is still active.
