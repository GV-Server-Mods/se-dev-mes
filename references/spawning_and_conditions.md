# MES Spawning Architecture & Conditions Reference

Deep-dive architectural guide to Modular Encounters Systems (MES) spawning algorithms, spawner types, environmental filters, threat calculations, and event spawning.

---

## 1. Spawner Types & Execution Pathways

MES categorizes all spawns into distinct operational streams:

| Spawner Type | Environment | Trigger Mechanism | Altitude & Placement |
| :--- | :--- | :--- | :--- |
| **Space Cargo Ship** | Space (Zero-G) | Periodic timer per active player | Spawns ~10–15km from player, travels in vector, despawns at end |
| **Planetary Cargo Ship** | Planet / Atmosphere | Periodic timer per active player | Spawns along planetary tangent at configured altitude, traverses waypoints |
| **Random Encounter** | Space | Player movement into unpopulated voxel/space sector | Static or slow-drifting wreckage/stations |
| **Planetary Installation** | Planet Surface | Player movement into unpopulated terrain sector | Voxel-aligned static bases, outposts, and towers |
| **Boss Encounter** | Space or Planet | Custom conditions, threat score, or MES Events | High-threat capital ships or fortified complexes |
| **Drone Encounter** | Space or Planet | RivalAI Trigger (`[Type:Damage]`, `[Type:PlayerNear]`) | Custom spawn around parent grid via `[RivalAI Spawn]` |
| **Event Encounter** | Space or Planet | MES Event Action (`[SpawnEncounter:true]`) | Spawned at exact coordinates or player offset |

---

## 2. Spawn Group Architecture (`<SpawnGroup>`)

A spawn group definition combines vanilla Keen tags with MES description tags:

```xml
<SpawnGroup>
  <Id>
    <TypeId>SpawnGroupDefinition</TypeId>
    <SubtypeId>ModPrefix-SpawnGroup-EncounterName</SubtypeId>
  </Id>
  <Description>
    [Modular Encounters SpawnGroup]
    [SpawnConditionsProfiles:ModPrefix-SpawnCondition-EncounterName]
    [ManipulationProfiles:ModPrefix-Manipulation-EncounterName]
  </Description>
  <IsPirate>true</IsPirate>
  <Frequency>5.0</Frequency>
  <Prefabs>
    <Prefab SubtypeId="ModPrefix-Prefab-EncounterName">
      <Position><X>0.0</X><Y>0.0</Y><Z>0.0</Z></Position>
      <Speed>15.0</Speed>
      <Behaviour>ModPrefix-Behavior-EncounterName</Behaviour>
    </Prefab>
  </Prefabs>
</SpawnGroup>
```

### Critical Spawn Group Tags:
- **[HARD] `[Modular Encounters SpawnGroup]` header**: `SpawnGroupManager.cs:647` only builds an MES spawn group when the Description contains this exact string. Any other header (e.g. `[MES Spawn Group]`) leaves it a plain vanilla spawn group: every MES tag in it is ignored, with no error.
- `<Frequency>`: Relative weight among eligible groups in the same pool. Higher frequency increases spawn probability relative to other groups.
- **[HARD] `<Frequency>` also weights a spawner's `[SpawnGroups:]` list.** A `[RivalAI Spawn]` (or event spawner) naming several groups picks one per spawn, weighted by each group's `<Frequency>`. `SpawnGroupManager.cs` stores `Frequency x 10` rounded with .NET `Math.Round` (banker's rounding, so `0.25` becomes `2`), adds the group to the pool that many times, and `SpawnGroupCollection.cs` picks uniformly from the pool. Groups are matched against the list with `Contains`, so listing a group twice adds no weight. **Fails as**: a group's Frequency applies to every spawner that lists it; to weight one spawner differently, give it its own copy of the group. A spawner with a single group ignores Frequency.
- **[HARD] Frequency below 0.05 never spawns, and values ending in 5 round unpredictably.** `<Frequency>` is a `float`, converted with `(int)Math.Round((double)Frequency * 10)` (`ImprovedSpawnGroup.cs:177`, MES `bc71965`). Float representation shifts the halfway cases: `0.05` → 1, `0.15` → 2, `0.25` → 2, `0.35` → 3, `0.45` → 4; `0.04` → 0. **Fails as**: a group at `0.04` or lower is never picked, with no error. Use multiples of `0.1` when the weights must be exact.
- **[HARD] A group with several `[SpawnConditionsProfiles:]` enters the pool once.** `SpawnGroupManager.cs` uses the first profile that passes and stops (`break`), so extra profiles widen where a group can spawn but never add weight.
- **[HARD] Static encounters are tracked by spawn group name.** `NpcManager.cs` drops a saved static-encounter record when no spawn group with that name (and a `StaticEncounter`/boss condition) exists any more, and then treats a static group it has no record of as new. **Fails as**: renaming a static encounter's spawn group on a live world spawns a second copy beside the one already there. Rename it only on a wipe, or delete the old grid first.
  - **Ground altitude & Water Mod [HARD]**: `StaticEncounter.cs:InitStaticEncounter` (fixed in `c35adb5`) measures planet-direction encounter altitude from the ground (`ignoreWater: true`). Previously, it measured from the higher of ground or water once the Water Mod registered, causing encounters below sea level to change altitude when re-created later.
  - **[HARD] Which conditions profile a static uses** (MES `bc71965`; these lines date from 2021, so they applied in January 2025 too). A static reads two profiles, chosen differently:
    - **The record** (trigger coords and radius, exact coords, forward/up, planet direction, faction): the **first** profile in list order with `[StaticEncounter:true]`, when the encounter is created at world load (`NpcManager.LoadNewStaticEncounters` -> `StaticEncounter.InitStaticEncounter`). The spawn group's Description is profile 0, so if it says `[StaticEncounter:true]`, the record comes from it.
    - **The spawn** (everything else: sandbox variables, zone conditions, threat, `[ForceExactPositionAndOrientation:]`, `[ForceStaticGrid:]`, `[RotateFirstCockpitToForward:]`, unique marking): the **first** profile that passes the spawn-type and common checks (`SpawnRequest.CalculateStaticSpawn` -> `SpawnGroupManager.GetSpawnGroups`, which stops at the first pass). On a planet a profile passes the spawn-type check only with `[StaticEncounter:true]`. The checks run at the **trigger coords**, not at the spawn point (`EnvironmentEvaluation(encounter.TriggerCoords)`), so strict-zone and zone conditions are tested there.
    - **Fails as**: a static whose Description sets `[StaticEncounter:true]` and its coords (each static needs its own coords, so they tend to go inline) plus `[SpawnConditionsProfiles:Shared]` for the common tags. Profile 0 is complete and passes first, so the shared profile is never used: its zone conditions, sandbox variables and rotation tags are ignored. This is what GVK hit in January 2025 (GVK-Derelicts `1aee79b` added zone conditions to a shared KOTH-Massive profile; `fd85248` moved them into each spawn group, which worked).
    - **Rule**: for statics, keep every condition tag in one profile per spawn group: either all in the Description (what GVK does now), or `[SpawnConditionsProfiles:]` alone with nothing but the header in the Description. **[HARD, tested in play]** For shared tags plus per-group coords, `[UseFirstConditionsAsPersistent:true]` makes profile 0 a gate (it supplies the record) and the spawn uses the next profile that passes; the shared profile then needs `[StaticEncounter:true]` and the placement tags.
  - **[HARD] Space statics can spawn with a profile that isn't a static one** (MES `bc71965`, since 2021; confirmed in play, reported as MeridiusIX/Modular-Encounters-Systems#417). `SpawningTypeAllowedForGroup` checks `type.HasFlag(StaticEncounterSpace) || type.HasFlag(StaticEncounterPlanet) && conditions.StaticEncounter` (`SpawnConditions.cs:177`); `&&` binds first, so off-planet every conditions profile passes the spawn-type check, with or without `[StaticEncounter:true]`, and the Description profile (index 0) is checked first. **Fails as**: a space static whose `[StaticEncounter:true]` lives in a `[SpawnConditionsProfiles:]` profile spawns with the Description's conditions instead (`ConditionIndex: 0` in `/MES.IGGD`); placement and faction still come from the static profile, but its other condition tags are ignored, and because the used profile has no `StaticEncounter`/`UniqueEncounter`, the group is not added to the unique-spawned list (`SpawnRequest.PostSpawn`), so the encounter is re-created at the next world load and spawns again (seen in a GVK test: deleted, saved, reloaded, and it came back; the `[UseFirstConditionsAsPersistent:true]` copy did not). Planet statics are not affected (that branch does require `[StaticEncounter:true]`). **Workaround**: put `[StaticEncounter:true]` and the static's condition tags in the spawn group's Description, or `[UseFirstConditionsAsPersistent:true]` so profile 0 is only a gate.
  - **Static encounter resets [HARD]**: `ResetThisStaticEncounter` (`NpcManager.cs`, fixed in `af492a5`) selects the first profile with `[StaticEncounter:true]` even if non-static condition profiles are listed ahead of it, and removes all duplicate entries from `UniqueGroupsSpawned`. To replace all spawned static encounters on a live world with fresh definitions without running Despawn actions, use `/MES.Debug.ResetStaticEncounters` (or `/MES.Debug.ResetStaticEncounters.Info` for dry run; §2D of `diagnostics_and_troubleshooting.md`).
- `[SpawnConditionsProfiles:]`: Reference to one or more `[MES Spawn Conditions]` profiles.
- `[ManipulationProfiles:]` / `[ManipulationGroups:]`: Reference to `[MES Manipulation]` profiles (block replacement, weapon randomizer, dereliction via `[UseGridDereliction:true]` + `[DerelictionProfiles:]`, inventory, recolor).
- `[ReplenishSystems:bool]` + `[ReplenishProfiles:]`: Spawn-group-level ammo/fuel top-up (§5 of `manipulation_and_dereliction.md`).
- **Inline profiles**: `ImprovedSpawnGroup.InitTags()` also parses the spawn group's own Description as its first Spawn Conditions profile and first Manipulation profile (`ImprovedSpawnGroup.cs:125-128`). Each `[SpawnConditionsProfiles:]` profile is **appended** after that inline profile, not merged into it (`TagParse.TagSpawnConditionsProfileCheck`), and MES checks every profile in the list separately; whichever one passes is the one used to spawn (size, placement, faction).
  - **[HARD]** Inline condition tags only take effect when the Description is a complete conditions profile on its own, i.e. it sets a spawn type (`[PlanetaryInstallation:true]`, `[SpaceCargoShip:true]`, ...). Without one, the inline profile never passes the spawn-type check (`SpawnConditions.SpawningTypeAllowedForGroup`, `SpawnConditions.cs:133-185`; checked in `SpawnGroupManager.cs:289-295`).
  - So a spawn group that uses `[SpawnConditionsProfiles:]` silently ignores condition tags written next to it in its Description (e.g. `[PlanetaryInstallationType:Large]`). Put them in the referenced `[MES Spawn Conditions]` profile instead. If the Description also sets a spawn type, it becomes a second, independent set of conditions, not an addition to the referenced profile.
  - `[UseFirstConditionsAsPersistent:true]` turns the inline profile into a gate every other profile must also pass (`SpawnGroupManager.cs:218-260`), but the spawn itself still uses the referenced profile that matched, so placement tags like `[PlanetaryInstallationType:]` still have to go there.
  - `[PlanetaryInstallationType:]` defaults to `Small` (`SpawnConditionsProfile.cs:391`); any value other than `Small`/`Medium`/`Large` is reset to `Small` (`SpawnConditions.cs:822-824`). A misplaced tag therefore gives a Small installation with no error.
- **[HARD] `<Enabled>false</Enabled>` removes a spawn group from MES entirely.** `SpawnGroupManager.cs:606` skips disabled definitions before parsing anything else. Redefining a vanilla or other-mod spawn group (same `TypeId`/`SubtypeId`) with `Enabled = false` in your own mod disables it everywhere, with no per-world config.

### Base-game spawn groups MES picks up [HARD]
MES loads every vanilla spawn group too, whatever the world's own encounter settings say:
- **`IsPlanetaryEncounter`** groups (`SpawnGroups_PlanetaryEncounters.sbc`, `P1_SupplyPost` ... `P30_AbandonedFarmstead`) become **Planetary Installations** (`SpawnGroupManager.cs:767-770`). Their `<PlanetaryInstallationSettings><Planets>` becomes the planet whitelist (`:864-873`); groups without one (`P28_LogisticsPost`, `P29_WreckedHopper`) spawn on any planet. With `EnablePlanetaryEncounters = false` in the world they still mix into your installation/wreck pools.
- **Ways to stop them:** the official add-on "Suppress Vanilla Planetary Installations" (Steam `3796756949`, detected in `AddonManager.cs:177`, applied by `ApplySuppression`, `SpawnGroupManager.cs:993-998`); redefining each group with `Enabled = false` (above); or listing them in `Config-General.xml` `NpcSpawnGroupBlacklist`. Sister add-ons exist for vanilla cargo ships (`888457124`) and space encounters (`888457381`).
- Their prefabs stay loaded and can be used by your own spawn groups. `audit_mes_references.ps1` resolves them through `scripts/vanilla_prefabs.json`.

---

## 3. Spawn Conditions Profile (`[MES Spawn Conditions]`)

Declared in an `Inventory` EntityComponent definition.

### A. Environment & Gravity Gates
- `[SpaceCargoShip:bool]`: Enables spawning in space cargo pools.
- `[LunarCargoShip:bool]`: Enables spawning in moon cargo pools.
- `[PlanetaryCargoShip:bool]`: Enables spawning in planetary cargo pools.
- `[SpaceRandomEncounter:bool]`: Enables static space encounters.
- `[PlanetaryInstallation:bool]`: Enables planetary base/station spawns.
- `[RivalAiSpawn:bool]` / `[RivalAiAnySpawn:bool]` / `[RivalAiSpaceSpawn:bool]` / `[RivalAiAtmosphericSpawn:bool]`: Make the group eligible for RivalAI `[RivalAI Spawn]` / event spawns (`SpawnConditions.cs:174` accepts any of the four).

### B. Planetary Altitude & Placement
- `[MinSpawnFromPlanetSurface:<double>]` & `[MaxSpawnFromPlanetSurface:<double>]`: Altitude window (meters above surface) at the spawn position; `-1` (default) disables each bound (`SpawnConditions.DistanceFromSurfaceCheck`). `[MinAltitude:]`/`[MaxAltitude:]` are `[RivalAI Spawn]` tags and are ignored here.
- `[AlignToSurface:bool]` *(MES 2.74.02)*: Planetary installations align to the terrain surface instead of the default gravity-up orientation.
- **Terrain checks [HARD]:** two tags read the same `[AllowedTerrainTypes:]` / `[DisallowedTerrainTypes:]` lists (voxel material `MaterialTypeName`, e.g. `Rock`, `Sand`, `Snow`), at different places:
  - `[InstallationTerrainValidation:true]` (planetary installations only): checks the terrain at each candidate spawn spot and skips spots that fail (`PathPlacements.IsPositionSurfaceValid`). Use this to keep installations off roads or rock. Only the centre point is checked, so a large prefab can still overhang the edge.
  - `[UseTerrainTypeValidation:true]` (any spawn type): checks the most common terrain within about 165 m of the player (`SpawnConditions.cs` ~429). Turning it on next to `InstallationTerrainValidation` also blocks the spawn whenever the player stands on a disallowed terrain.
  - The MES wiki only documents the player-area meaning and has no `DisallowedTerrainTypes` card.
- Water Mod installations: `[InstallationSpawnsOnWaterSurface:bool]` / `[InstallationSpawnsUnderwater:bool]` with `[MinWaterDepth:<double>]` / `[MaxWaterDepth:<double>]` *(MaxWaterDepth added in 2.74.03)*. **[HARD]** The placement check rejects depths below `MinWaterDepth` or above `MaxWaterDepth` (`PathPlacements.cs:836-845`). Since MES 2.74.05 `MaxWaterDepth` defaults to `-1` (no maximum). In 2.74.03-2.74.04 it defaulted to `0`, which rejected every water-surface/underwater station and underwater creature placement unless it was set. `[MaxWaterDepth:0]` still allows no water placement (creatures spawn on dry land only).
- `[CutVoxelsAtAirtightCells:true]`: **[HARD]** Cuts terrain meshes only around airtight cells of subterranean stations.
- `[CutVoxelSize:<double>]`: Voxel cut buffer size in meters (e.g. `2.5`).
  > [!WARNING]
  > Never use `[CutVoxels:true]` on `[MES Spawn Conditions]`. It does not exist and silently fails. `<CutVoxels>true</CutVoxels>` is Keen's vanilla XML tag for `<SpawnGroup>`.

### C. Threat Score & Combat Readiness
MES evaluates player threat score based on block count, weapons, and grid mass in range:
- `[UseThreatLevelCheck:true]`
- `[ThreatScoreMinimum:<int>]` & `[ThreatScoreMaximum:<int>]`
- `[ThreatLevelCheckRange:<double>]`: Radius around spawn point to calculate player threat (default: 5000m).
- `[ThreatScoreGridConfiguration:All]` (or `Static`, `Dynamic`).
- `[ThreatIncludeOtherNpcOwners:bool]`, `[ThreatScorePlanetaryHandicap:<float>]`.

### D. Weather, Day/Night & Sandbox Variables
- `[UseWeatherSpawning:true]` + `[AllowedWeatherSystems:Fog,Dust,Sandstorm]`: Requires active planet weather.
- `[UseDayOrNightOnly:true]` + `[SpawnOnlyAtNight:bool]`: Day/night gate (`false` = day only).
- `[SandboxVariables:...]` / `[FalseSandboxVariables:...]`: Sandbox booleans that must be true / false. `{SpawnGroupName}` resolves in both *(MES 2.74.00)*.
- `[CheckCustomSandboxCounters:true]` + `[CustomSandboxCounters:...]` + `[CustomSandboxCountersTargets:...]` + `[SandboxCounterCompareTypes:...]` (targets list is zero-stripped — see `events_and_zones.md` §3).
- `[UseRandomCustomFaction:bool]` *(MES 2.74.00)*: Completes the random-faction set alongside the existing faction randomizers.

### E. Economy Item Contracts
- `[EnableItemTriggeredContracts:bool]` *(MES 2.74.03, default `false`; forced `true` for converted vanilla SpawnGroups)*: lets Keen's item-triggered delivery contracts seed a data item into the encounter's cargo. Needs world Economy on. Full mechanics and caveats: [`economy_and_stores.md`](economy_and_stores.md) §4.

---

## 4. RivalAI Grid-Bound Spawner (`[RivalAI Spawn]`)

Used inside Action profiles (`[Spawner:<SubtypeId>]`) to deploy escorts, defense drones, or reinforcements around a live grid.

```xml
<EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
  <Id>
    <TypeId>Inventory</TypeId>
    <SubtypeId>ModPrefix-Spawner-DefenseDrone</SubtypeId>
  </Id>
  <Description>
    [RivalAI Spawn]
    [UseSpawn:true]
    [SpawningType:CustomSpawn]
    [FirstSpawnTimeMs:0]
    [SpawnGroups:ModPrefix-SpawnGroup-DefenseDrone]
    [MinDistance:150]
    [MaxDistance:300]
    [MinAltitude:30]
    [MaxAltitude:60]
    [InheritNpcAltitude:true]
  </Description>
</EntityComponent>
```

- **Required Gate**: `[UseSpawn:true]`
- `[SpawningType:CustomSpawn]`: Spawns relative to parent grid.
- `[MinDistance:<double>]` & `[MaxDistance:<double>]`: Radial distance from parent.
- `[InheritNpcAltitude:bool]`: Aligns drone altitude to parent grid's altitude.
- `[FirstSpawnTimeMs:<int>]`, `[SpawnMinCooldown:<int>]` / `[SpawnMaxCooldown:<int>]`, `[MaxSpawns:<int>]`: Timing and cap. `[StartsReady:true]` *(parsed since MES 2.74.04; ignored before)* lets the **first** spawn skip the cooldown; later spawns still wait for it (`SpawnProfile.IsReadyToSpawn`).

---

## 5. MES Event Spawner (`[MES Event Action]`)

Used by global session-level events to spawn encounters at precise coordinates:

```xml
<EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
  <Id>
    <TypeId>Inventory</TypeId>
    <SubtypeId>ModPrefix-EventAction-SpawnConvoy</SubtypeId>
  </Id>
  <Description>
    [MES Event Action]
    [SpawnEncounter:true]
    [SpawnCoords:{X:60487.11 Y:32965.06 Z:44090.29}]
    [SpawnFactionTags:GAALSIEN]
    [SpawnFactionTags:SPRT]
    [SpawnData:ModPrefix-EventSpawner-Convoy]
  </Description>
</EntityComponent>
```

### Critical Event Spawner Rules:
1. **Tag Name**: Must use `[SpawnData:<SubtypeId>]`, NOT `[Spawner:]`.
2. **Master Gate**: Must declare `[SpawnEncounter:true]`.
3. **List Alignment**: `SpawnCoords`, `SpawnFactionTags`, and `SpawnData` must have strictly identical element counts.
4. **Special Flags on Spawner Profile**:
   - `[ProcessAsAdminSpawn:true]`: Bypasses standard player distance and safezone spawn rejection.
   - `[IgnoreSafetyChecks:true]`: Allows spawning near player grids or structures for scripted set-pieces.
   - `[InheritNpcAltitude:false]`: Uses absolute coordinate altitude rather than raycasting from a non-existent parent.

---

## 6. Faction Resolution & The Silent Spawn Rejection Pipeline [HARD]

When an NPC spawn group is evaluated for spawning, MES resolves the owning faction tag before any grid is spawned. If the faction tag does not exist or has a typo, **the spawn group is silently discarded with a 0% spawn rate and no in-game warning or crash**.

### A. The Resolution Code (`SpawnConditions.cs:2144-2168`)
During `ValidNpcFactions()`, MES queries the active session factions:
```csharp
var initialFaction = MyAPIGateway.Session.Factions.TryGetFactionByTag(initialFactionTag);

if (initialFaction != null) {
    factionList.Add(initialFaction);
} else {
    if (initialFactionTag == "Nobody") {
        resultList.Add("Nobody");
    }
    else if (initialFactionTag == "UseBaseGameFactionTags") {
        foreach (var baseGameTags in spawnGroup.BaseGameFactionTags) {
            resultList.Add(baseGameTags);
        }
    }
    return resultList; // <--- Returns an EMPTY list (Count == 0)!
}
```

### B. The Silent Drop (`SpawnGroupManager.cs:307-314`)
When `ValidNpcFactions()` returns an empty list, `SpawnGroupManager` immediately skips the group:
```csharp
var validFactionsList = SpawnConditions.ValidNpcFactions(spawnGroup, conditions, environment.Position, overrideFaction, forceSpawn, collection);

if (validFactionsList.Count == 0 && collection.OwnerOverride < 0) {
    SpawnLogger.Queue("   - Could Not Get Valid NPC Faction.", SpawnerDebugEnum.SpawnGroup, addToReason: true);
    continue; // Rejects group from eligible spawn pool!
}
```
- The group is never added to `collection.SpawnGroupSublists`.
- It has an absolute **0% chance of spawning naturally**.
- **Admin Force-Spawning Fails**: Even `/mes spawn <SpawnGroup>` evaluates `ValidNpcFactions()`, which still returns 0 factions and fails to spawn.

### C. Points of Failure & Where Typos Occur
1. **`[FactionOwner:<Tag>]` in `[MES Spawn Conditions]`**: Default is `SPRT`. A typo here (e.g. `SPTR`) breaks all spawn conditions referencing the tag.
2. **`[FactionOverride:<Tag>]` in the `[Modular Encounters SpawnGroup]` Description**: Overrides `FactionOwner`. A typo here breaks the entire spawn group.
3. **`[UseAllowedFactions:true]` + `[AllowedFactions:<Tag>]` in `[MES Zone]`** *(MES 2.74.00)*: In `SpawnConditions.cs:2096`, if the resolved faction is not in the zone whitelist, spawning fails with:
   `"Zone Check Failed: Faction '<tag>' is not among Allowed Zone Factions."` (`[UseRestrictedFactions:true]` + `[RestrictedFactions:]` is the blacklist twin, line 2120.)
4. **`[SpawnFactionTags:<Tag>]` in `[MES Event Action]`**: Used with `[SpawnEncounter:true]`.
5. **Missing Mod in World Save**: If a mod defining custom factions in `Factions.sbc` is omitted from the world save, or if `Factions.sbc` had XML syntax errors preventing it from loading, Space Engineers never registers the faction in `Session.Factions`, silently disabling all spawns for that faction.

### D. Special Reserved Keywords (Bypassing Faction Lookup)
- **`"Nobody"`**: Spawns the grid as completely unowned (neutral derelicts/stations).
- **`"UseBaseGameFactionTags"`**: Instructs MES to read the vanilla `<FactionSubtypeIds>` defined directly in the `<SpawnGroup>` XML.

### E. Faction Tag Conventions & Tiered Classification
1. **Player vs. NPC Faction Length**:
   - In Space Engineers, player-created factions in the GUI are strictly **3 characters**.
   - NPC factions defined in `Factions*.sbc` should use **4 or more characters** (e.g. `SPRT`, `SPID`, `GAALSIEN`) to prevent naming collisions with player-created factions.
2. **Tiered Validation**:
   - **Tier 1 (Primary & Declared)**: `SPRT`, `SPID`, reserved keywords (`Nobody`, `UseBaseGameFactionTags`), plus any faction declared in local `Factions*.sbc`. Pass silently.
   - **Tier 2 (Obscure Vanilla / Economy / Campaign)**: `CIVL`, `TRAD`, `ROBO`, `FSD`, `STEJ`, `KRI`, `INDEP`, `SHIV`, `GTI`, `ROS`, `AMPH`, `BLDR`, `MINR`, `MILT`, `PIR8`, `RED`, `BLU`. Flagged as `[INFO]` (soft notice) since modders rarely target Keen economy/campaign factions and they require specific world settings to exist.
   - **Tier 3 (Unrecognized / Typo)**: Any undefined tag causes silent 0% spawn drops and is flagged as `[WARN]`.
3. **IdsReplacer Incompatibility with Pre-Spawn Faction Tags**:
   - `IdsReplacer` runs only at runtime on active grids with `NpcData` (e.g., chat, GPS, LCDs, and `PlayerConditionProfile.CheckReputationwithFaction`).
   - `SpawnConditions.cs` (`ValidNpcFactions`) and `EventActionExecution.cs` (`[SpawnFactionTags]`) evaluate pre-spawn before `NpcData` exists.
   - Using dynamic tokens like `{Faction}`, `{Attacker}`, or `{SandboxVar}` inside `[FactionOwner:]`, `[FactionOverride:]`, `[SpawnFactionTags:]`, or `[CheckReputationAgainstOtherNPCFaction:]` causes a literal string lookup in session factions that fails, permanently locking the encounter to 0% spawn rate. Flagged as `[ERROR]`.


