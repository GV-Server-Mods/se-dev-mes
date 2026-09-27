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
- `[SpawnConditionsProfiles:]`: Reference to one or more `[MES Spawn Conditions]` profiles.
- `[ManipulationProfiles:]` / `[ManipulationGroups:]`: Reference to `[MES Manipulation]` profiles (block replacement, weapon randomizer, dereliction via `[UseGridDereliction:true]` + `[DerelictionProfiles:]`, inventory, recolor).
- `[ReplenishSystems:bool]` + `[ReplenishProfiles:]`: Spawn-group-level ammo/fuel top-up (§5 of `manipulation_and_dereliction.md`).
- **Inline profiles**: `ImprovedSpawnGroup.InitTags()` also parses the spawn group's own Description as its first Spawn Conditions profile and first Manipulation profile, so condition/manipulation tags written directly in the spawn group are honored.

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
- Water Mod installations: `[InstallationSpawnsOnWaterSurface:bool]` / `[InstallationSpawnsUnderwater:bool]` with `[MinWaterDepth:<double>]` / `[MaxWaterDepth:<double>]` *(MaxWaterDepth added in 2.74.03)*. **[HARD]** The placement check rejects any depth outside `[Min, Max]` (`PathPlacements.cs:836-845`) and `MaxWaterDepth` defaults to `0`, so always set it for water-surface or underwater stations.
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


