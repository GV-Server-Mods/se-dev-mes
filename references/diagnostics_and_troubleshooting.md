# In-Game Diagnostics, Logging & Troubleshooting Reference

Diagnostic reference covering in-game admin chat commands, log file auditing, sim-speed optimization, anti-clang physics mitigations, and common error signatures.

---

## 1. Action & Trigger Debugging: [DebugMessage] vs. Chat Profiles

When testing whether triggers fire and actions execute, **never create throwaway `[RivalAI Chat]` profiles**. Doing so introduces redundant `<EntityComponent>` blocks, bloats XML, and clutters cross-referencing. Instead, use native MES debug tags:

### A. RivalAI Action Debugging
- **Tag**: `[DebugMessage:<Your Debug Message Here>]`
- **Location**: Inside `[RivalAI Action]` or `[MES AI Action]`.
- **Mechanism** (`ActionSystem.cs:3047`):
  - Sends a chat message to all players attributed to the grid name.
  - Automatically evaluates dynamic replacement tokens: `{Faction}`, `{Position}`, `{PlayerName}`, etc.
  - Automatically evaluates grid custom counter variables: `{<CounterName>}`.
  - Example:
    ```xml
    <Description>
      [RivalAI Action]
      [DebugMessage:TRIGGER FIRED: Health < 50% | Counter: {DamageCounter} | Faction: {Faction}]
      [ChangeBehaviorSubclass:true]
      [NewBehaviorSubclass:Fighter]
    </Description>
    ```

### B. MES Event Action Debugging
- **Tags**: `[DebugChatMessage:<Text>]` and `[DebugHudMessage:<Text>]`
- **Location**: Inside `[MES Event Action]`.
- **Mechanism** (`EventActionExecution.cs:701-716`):
  - `[DebugChatMessage:<Text>]`: Sends an in-game chat message attributed to the Event Action's SubtypeId with token evaluation.
  - `[DebugHudMessage:<Text>]`: Sends an on-screen HUD notification (3000ms duration) and a chat line to all players.
  - Example:
    ```xml
    <Description>
      [MES Event Action]
      [DebugHudMessage:EVENT EXECUTED: Territory Ladder Up triggered!]
      [ChangeCounters:true]
      [IncreaseCounters:TerritoryPoints]
      [IncreaseCountersAmount:10]
    </Description>
    ```

### C. Strict Production Rule
> [!WARNING]
> **Remove Debug Tags Before Production Release**:
> - `[DebugMessage]` is strictly a development diagnostic. It sends raw chat messages to all players without checking player distances, faction relations, broadcast radius, or radio antennas.
> - **Never** use `[DebugMessage]` as a substitute for real NPC chat messages.
> - For in-game player-facing dialogue, always use dedicated `[RivalAI Chat]` profiles configured with proper broadcast range (antenna range, or `[IgnoreAntennaRequirement:true]` + `[IgnoredAntennaRangeOverride:<m>]`), `[BroadcastChatType:]`, colors, and audio.

---

## 2. In-Game Admin Diagnostics & Logging Commands

MES and RivalAI include deep runtime logging and telemetry systems that can be toggled on-the-fly via in-game admin chat.

### A. Spawner Logging (`/MES.SpawnDebug.<Type>.<true/false>`)
Controls verbose diagnostic logging for the encounter spawner. Set `<Type>` to any of the following:

| Spawner Debug Type | Diagnostic Information Logged |
| :--- | :--- |
| `Spawning` | Spawner candidate evaluation, spawn distance checks, and final spawn execution. |
| `SpawnGroup` | Detailed eligibility breakdown (why each spawn group passed or failed its conditions). |
| `Zone` | Zone boundary detection, zone condition filters, and restricted spawn group checks. |
| `Pathing` | Spawner trajectory, altitude checks, and waypoint pathing generation. |
| `Manipulation` | Block replacement, weapon randomization, dereliction damage, and loot injection. |
| `CleanUp` | Grid despawn distance scans, player proximity checks, and cleanup timer evaluations. |
| `PostSpawn` | Post-spawn physics stabilization, ownership assignment, and AI attachment. |
| `GameLog` | Routes all spawner debug messages directly to `SpaceEngineers.log`. |

Also valid (`SpawnerDebugEnum`): `API`, `BlockLogic`, `Entity`, `Error`, `Settings`, `Startup`, `SpawnRecord`, `Dev`.

- **Example**: Enable detailed spawn group condition logging and send output to `SpaceEngineers.log`:
  ```
  /MES.SpawnDebug.SpawnGroup.true
  /MES.SpawnDebug.GameLog.true
  ```

### B. Behavior & AI Logging (`/MES.BehaviorDebug.<Type>.<true/false>`)
Controls verbose diagnostic logging for RivalAI grid behaviors. Set `<Type>` to any of the following:

| Behavior Debug Type | Diagnostic Information Logged |
| :--- | :--- |
| `Trigger` | Condition evaluation results, execution cooldowns, and trigger firing events. |
| `Action` | Action execution steps, variable mutations, and unhandled action failures. |
| `Condition` | Granular condition checks (custom counters, sandbox booleans, distance, speed). |
| `AutoPilot` | Waypoint navigation, collision evasion vectors, and flight mode calculations. |
| `TargetAcquisition`| Target scan passes, relation filtering, and potential target candidate lists. |
| `TargetEvaluation` | Target priority scoring, distance weighting, and subsystem target locking. |
| `Weapon` | WeaponCore/vanilla turret range clamping, firing sequences, and ammo checks. Per-gun status such as `NoAmmo`, `StaticWeaponNotAligned`, `ReadyToFire` (see `aircraft_behaviors_and_tuning.md` section 6). |
| `Command` | Squad radio command transmissions, frequency matches, and recipient processing. |
| `Chat` | Chat broadcast range checks, relation filtering, and broadcast transmission. |
| `Collision` | Raycasting results, asteroid/terrain obstacle avoidance, and evasion maneuvers. |
| `Despawn` | Timeout timers, player distance retreat checks, and force-despawn execution. |
| `BehaviorMode` | Subclass switching (`ChangeBehaviorSubclass`) and state transitions. |
| `BehaviorSetup` | Remote Control registration and behavior attachment at spawn (first stop when a grid has no AI at all). |
| `Owner` | Remote Control and grid ownership handling. |
| `General` | Behavior-manager messages, including `Exception in Parallel Calculations`. |
| `Error` | Caught exceptions. |
| `GameLog` | Routes all behavior debug messages directly to `SpaceEngineers.log`. |

Also valid (`BehaviorDebugEnum`): `BehaviorSpecific`, `Settings`, `Spawn`, `Startup`, `Target`, `Thrust` (logs thruster removal only), `Dev`, `BehaviorLog`.

- **Example**: Track why a combat trigger isn't firing:
  ```
  /MES.BehaviorDebug.Trigger.true
  /MES.BehaviorDebug.Condition.true
  /MES.BehaviorDebug.Action.true
  /MES.BehaviorDebug.GameLog.true
  ```

### C. Clipboard Export Commands (`/MES.Info.*`)
MES can dump internal diagnostic logs directly to your Windows clipboard for fast analysis without digging through log files:

| Chat Command | Shortcut | Data Copied to Windows Clipboard |
| :--- | :--- | :--- |
| `/MES.Info.GetLogging.SpawnDebug.<Type>` | `/MES.IGLSD.<Type>` | Copies one spawner log buffer, e.g. `/MES.IGLSD.SpawnGroup`. |
| `/MES.Info.GetLogging.BehaviorDebug.<Type>` | `/MES.IGLBD.<Type>` | Copies one behavior log buffer, e.g. `/MES.IGLBD.Trigger`. |
| `/MES.Info.GetGridBehavior` | `/MES.IGGB` | Dumps targeted grid's active behavior, autopilot, and trigger states. |
| `/MES.Info.GetGridData` | `/MES.IGGD` | Dumps targeted grid's core MES entity parameters. |
| `/MES.Info.GetEligibleSpawnsAtPosition` | `/MES.GESAP` | Lists all spawn groups eligible to spawn at the player's current location. |
| `/MES.Info.GetThreatScore` | `/MES.GTS` | Calculates and displays player combat threat score at current position. |
| `/MES.Info.GetDiagnostics` | `/MES.IGD` | General diagnostic telemetry dump. |

**[HARD] The `<Type>` is required** on `GetLogging` (`LoggerTools.GetLogging` needs 5 parts): a bare `/MES.IGLBD` or `/MES.IGLSD` only returns `Command Missing Parameters.` Each debug type has its own buffer, so copy each type you enabled (`.Trigger`, `.Condition`, `.Action`, …).

### D. Spawning & Encounter Force-Spawn Commands
- `/MES.Spawn.<Type>.<SpawnGroupName>` (`ChatMessage.ProcessSpawn`): runs a spawn of that type at your position; with the optional `.<SpawnGroupName>` it tries only that group (still subject to its conditions). Parts are split on `.`, so a SpawnGroup name containing a dot cannot be named here. Types and shortcuts: `SpaceCargoShip` (`/MES.SSCS`), `RandomEncounter` (`/MES.SRE`), `PlanetaryCargoShip` (`/MES.SPCS`), `PlanetaryInstallation` (`/MES.SPI`), `BossEncounter` (`/MES.SBE`), `Creature` (`/MES.SC`), `DroneEncounter` (`/MES.SDE`), `Prefab` (`/MES.SP`), `PrefabStation` (`/MES.SSP`). **[HARD]** `/MES.SSE` is rewritten to `/MES.Spawn.StaticEncounter`, which `ProcessSpawn` does not handle (reply: `No Spawning Type From Chat`); statics spawn when a player comes near, and reset with the commands below. It is an admin spawn: spawn timeouts and the global NPC cap are skipped, every other condition still applies, and the group needs a conditions profile with the matching spawn type (table in `testing_and_debugging.md` §2). Also `/MES.Spawn.WaveSpawner.<Space|Planet|Creature>` and `/MES.Spawn.ForceSpawnTimer`.
- There is no chat command to toggle all MES spawning, reset all counters or GPS-mark encounters; use `/MES.Debug.ChangeCounter` / `ChangeBool` below for single values and `/MES.Info.GetActiveNpcs` to list live NPCs.
- `/MES.Debug.ShowZone.<PublicName|ZoneSubtypeId>`, `/MES.Debug.HideZone.<...>`, `/MES.Debug.ShowAllZones`, `/MES.Debug.HideAllZones` *(2.74.04)*: Draw zone spheres (including multi-sphere zones) in-world, with temporary GPS markers.
- `/MES.Debug.CreateKPL.<Faction>.<Radius>.<Minutes>.<MaxEncounters>.<MinThreat>`: Creates a Known Player Location at your position. Minutes defaults to `30`; since 2.74.04 a value of `0` or less creates nothing (HUD: `KPL Not Created: Duration Must Be Greater Than 0`).
  - `ShowAllZones` draws KPLs too (they are active zones), but the visualizer keys zones by `PublicName`, then `Name`, and KPLs have neither, so only **one** KPL is drawn at a time and `ShowZone` cannot target a KPL (`ZoneDebugVisualizer.GetZoneKey`). Still the quickest way to see whether a KPL exists and how far it reaches.
- `/MES.Debug.DrawPaths`: toggles in-world lines from every AI-ready NPC to its waypoints (`AutoPilotSystem.DebugDrawingToWaypoints`): **green** current waypoint, **cyan** offset waypoint (attack-run line-up, escort slot), **magenta** planet-pathing waypoint, **red/orange** collision evasion. Drawn from the behavior loop, so it shows in singleplayer or on the hosting machine **[SOFT]: not expected to show for a client of a dedicated server**.
- `/MES.Debug.ChangeBool.<Name>.<true|false>`: sets a sandbox boolean. `/MES.Debug.ChangeCounter.<Name>.<Amount>`: **adds** `<Amount>` to a sandbox counter (use a negative amount to subtract; it is not a set).
- `/MES.Debug.ClearUniqueEncounters`: forgets which `UniqueEncounter` spawn groups have spawned. `/MES.Debug.ClearStaticEncounters`: invalidates every saved static-encounter record, so statics respawn.
- `/MES.Debug.ResetStaticEncounters` *(MES 2.75.00 / PR #389)*: replaces every spawned static encounter in the world with a fresh copy from current definitions (useful after a mod update changed prefabs, behaviors, or coordinates). Grids are closed directly (bypassing Despawn handling and Compromised/Despawn triggers) and re-spawned immediately. Skips any encounter whose grids have player-owned blocks (`FactionHelper.IsIdentityPlayer`), players seated, foreign attached grids, or other entities within 250m.
- `/MES.Debug.ResetStaticEncounters.Info`: dry-run report for `ResetStaticEncounters`; evaluates every spawned static encounter, reports which would reset or be skipped (with reasons), copies output to the clipboard, and writes to `SpawnRecord.log`.
- `/MES.Debug.ResetThisStaticEncounters.<SpawnGroupName>`: resets a single named static encounter so it respawns when players next approach. Fixed in commit `af492a5` to scan for the first `[StaticEncounter:true]` condition profile rather than aborting if non-static condition profiles are listed first.

### E. No `/RivalAI.*` Commands
RivalAI is merged into MES; current MES has no `/RivalAI.*` chat commands (none are parsed in `Sync/ChatMessage.cs`). For a grid's live AI state use `/MES.IGGB` (§C), and `/MES.Debug.DrawPaths` (§D) for waypoints.

---

## 3. The Agent Troubleshooting Protocol (When Something Fails)

When a modder reports that an encounter is not spawning, triggers aren't firing, or an NPC is behaving abnormally, write them a test procedure following [`testing_and_debugging.md`](testing_and_debugging.md): spawn the NPC with an MES spawn command (§2 there), check visually with the debug commands first (§3), then debug chat messages (§4), then logs (§5, summarised below), and only as a last resort debug lines in the local MES copy (§6).

> [!TIP]
> **Look before you log.** MES logs are long and slow to work through. Start with the visual tools and only turn on logging if they don't explain the problem:
> - **Autopilot** (wrong path, overshoot, never lines up): `/MES.Debug.DrawPaths`, then `/MES.IGGB` on the grid for mode, subclass, autopilot profile and `Forward Thrust Mode`.
> - **Zones and KPLs** (spawns blocked or allowed in the wrong place): `/MES.Debug.ShowAllZones`.
> - **Spawning**: `/MES.GESAP` at the spot lists the eligible spawn groups.
>
> Give the user the exact commands for whatever they are testing, including the spawn command and where to stand.

Log workflow, once the visual checks and debug messages don't explain it:

1. **Step 1: Spawner Failures** (Encounter won't spawn or wrong ship appears):
   - Instruct the user to run:
     ```
     /MES.SpawnDebug.SpawnGroup.true
     /MES.SpawnDebug.Spawning.true
     ```
   - Attempt a spawn (or run `/MES.GESAP` at the intended spawn position).
   - Run `/MES.IGLSD.SpawnGroup` (and `/MES.IGLSD.Spawning`) and paste the clipboard output to the agent.
   - The output will state the exact condition that failed (e.g. `ThreatScore Too High`, `MinAltitude Failed`, `Zone Condition Mismatch`).

2. **Step 2: Trigger / Action Failures** (NPC ignores player, weapons don't shoot, reinforcements don't spawn):
   - Instruct the user to target the grid and run:
     ```
     /MES.BehaviorDebug.Trigger.true
     /MES.BehaviorDebug.Condition.true
     /MES.BehaviorDebug.Action.true
     ```
    - Engage or shoot the grid to trigger the event.
    - Run `/MES.IGLBD.Trigger` (then `.Condition`, `.Action`) and paste the clipboard output to the agent.
    - The output will identify whether the trigger evaluated false, failed a cooldown check, or threw an action error.

3. **Step 3: Deep-Dive / Complex Issues (The GameLog File Workflow)**:
   - When issues are intermittent, complex, or the clipboard buffer overflows, instruct the user to route debug output directly into Keen's game log:
     ```
     /MES.SpawnDebug.GameLog.true
     /MES.BehaviorDebug.GameLog.true
     ```
   - **Log File Locations**:
     - Client / Singleplayer: `%AppData%\SpaceEngineers\SpaceEngineers.log` or timestamped session logs (e.g. `SpaceEngineers_20260919_090818200.log`).
     - Dedicated Server: `SpaceEngineersDedicated.log` in the server instance folder.
   - **Agent Inspection**: The user points the AI agent directly to the log file path. The agent inspects the file using search tools to trace exact timestamps, tag evaluations, and unhandled exceptions without requiring manual copy-pasting.
   - **Disable When Finished**:
     ```
     /MES.SpawnDebug.GameLog.false
     /MES.BehaviorDebug.GameLog.false
     ```

4. **Step 4: Disable Debugging After Diagnosis**:
   - Instruct the user to disable debug flags to prevent log spam:
     ```
     /MES.SpawnDebug.Spawning.false
     /MES.BehaviorDebug.Trigger.false
     ```

---

## 4. Log Auditing & Common Error Signatures (`SpaceEngineers.log`)

When troubleshooting encounter loading or execution failures, search `SpaceEngineers.log` for the following signatures:

### 1. `System.Xml.XmlException: Unexpected node type Comment`
- **Cause**: XML comment (`<!-- ... -->`) placed inside a `<Description>` tag.
- **Result**: `MOD_CRITICAL_ERROR` — Keen's `ReadElementString()` crashes and skips loading the mod entirely.
- **Fix**: Replace XML comments with RivalAI comment syntax: `[//Comment text]`.

### 2. `Could Not Load Action Profile From Trigger: : [SubtypeId]`
- **Cause**: Duplicate `<SubtypeId>` elements inside a single `<Id>` block.
- **Result**: Deserializer discards the second SubtypeId, leaving the referenced profile undefined.
- **Fix**: Separate into individual `<EntityComponent>` blocks, each with its own `<Id>`.

### 3. `Counter Names and Targets List Counts Don't Match`
- **Cause**: The Zero-Stripping Bug. `TagIntListCheck` in `TagParse.cs` stripped a `0` from `[CustomCountersTargets:0]`.
- **Result**: The condition profile fails to evaluate.
- **Fix**: Use `[CustomCountersTargets:-1]` with `[CounterCompareTypes:LessOrEqual]` or `[CounterCompareTypes:Greater]`.

### 4. `System.ArgumentOutOfRangeException: Index was out of range... CargoShipWaypoints`
- **Cause**: `[Type:WaypointNear]` / `[Type:WaypointFar]` read `AutoPilot.State.CargoShipWaypoints[0]` with no count check (`TriggerChecks.CheckWaypointNear`/`Far`). Only `[BehaviorName:CargoShip]` fills that list; on any other behavior, or once a CargoShip has used up its waypoints, it is empty.
- **Result [HARD]**: the exception escapes `ProcessTriggersParallel`, so `BehaviorManager.ProcessParallelMethods` catches it and resets `Mode` to `Parallel` instead of `MainThread`. The main-thread pass (`ProcessAutoPilotMain`, `ProcessWeaponsMain`, `ProcessTriggersMain`, `ProcessDespawnConditions`, `ProcessMainBehavior`) then never runs for **any** NPC on the server while that grid exists: every MES AI stops acting, not just this grid. The log repeats `Exception in Parallel Calculations`.
- **Fix**: Remove the trigger, or use one that measures what you meant:
  - Arrival at a Patrol point: `[Type:BehaviorTriggerA]` (`Patrol.cs` sets it on reaching the offset waypoint; what A–G mean differs per behavior, so check that behavior's `.cs` before using one elsewhere).
  - A fixed spot: `[Type:Position]` + `[GlobalPosition:{X:… Y:… Z:…}]` + `[TargetDistance:]` (distance from the Remote Control).
  - Not `[Type:TargetNear]`/`[Type:TargetFar]`: those measure distance to the current **target**, not a waypoint.
  - `WaypointNear`/`Far` are safe only on `CargoShip` behaviors while waypoints remain.

### 5. `System.IndexOutOfRangeException: Index was outside the bounds of the array... ChangeBlocksShareModeAll`
- **Cause**: The inner block loop indexed `AllTerminalBlocks[i]` (the grid index) instead of `[j]`, so the action threw or hit the wrong blocks.
- **Status**: **Fixed in MES 2.74.04** (PR #369). `[ChangeBlocksShareModeAll:true]` + `[BlockNamesShareModeAll:Name1,Name2]` now sets share-mode All on every terminal block across the NPC's linked grids whose `CustomName` exactly matches. If you still see this exception, the server is running MES older than 2.74.04.

### 6. Prefab SubtypeId vs. File Name Mismatch (Silent Spawn Failure / `Prefab Not Found`)
- **Cause**: The `SpawnGroup` references a prefab by its SubtypeId (e.g. `<Prefabs><Prefab SubtypeId="MyPatrolDrone">`), but the prefab file on disk has a different internal SubtypeId.
- **The Critical Rule**: **Space Engineers and MES completely ignore the prefab's file name on disk** (`MyPatrolDrone.sbc`). Spawning resolves *strictly and exclusively* against the `<Id><SubtypeId>` element declared inside the prefab XML:
  ```xml
  <Prefabs>
    <Prefab>
      <Id>
        <TypeId>MyObjectBuilder_PrefabDefinition</TypeId>
        <SubtypeId>MyPatrolDrone</SubtypeId> <!-- MUST MATCH THE SPAWNGROUP -->
      </Id>
    ...
  ```
- **Symptom**: Spawning silently fails, or `SpaceEngineers.log` reports `Prefab [MyPatrolDrone] was not found in PrefabManager` or `NullReferenceException` in `SpawnProcess`.
- **Fix**: Verify that the `<SubtypeId>` inside `Data/Prefabs/<FileName>.sbc` matches the `SubtypeId` in your `SpawnGroupDefinition` verbatim.

### 7. The `.sbcB5` Stale Binary Cache Trap
- **Cause**: When Space Engineers or the Dedicated Server loads a prefab `.sbc` for the first time, it compiles and caches it into a binary `.sbcB5` file in the same `Data/Prefabs/` folder. When a modder subsequently modifies the prefab `.sbc` (updating blocks, changing names, re-exporting, or tweaking weapon mounts), the game frequently **ignores the updated `.sbc` text file and loads the stale `.sbcB5` binary file instead**.
- **Symptom**:
  - In-game spawned grids do not reflect recent block changes or terminal renames.
  - Spawning fails or throws deserialization errors due to outdated grid offsets.
  - WeaponCore or RivalAI behaviors fail because newly added blocks are missing from the loaded binary cache.
- **Fix**: **Always delete the `.sbcB5` binary file whenever modifying a prefab.**
  ```powershell
  # Remove all stale sbcB5 cache files across prefabs
  Get-ChildItem -Path "Data/Prefabs" -Filter "*.sbcB5" -Recurse | Remove-Item -Force
  ```
  Keen will recompile fresh binary caches from the updated XML on the next world load.

### 8. Spawning As "Nobody" / Inactive AI (Missing or Dead Remote Control)
- **Cause**: The spawned prefab does not contain an undamaged, operational `MyObjectBuilder_RemoteControl` block, or the Remote Control block is not owned by the spawning NPC faction.
- **Result**: The grid spawns as unowned ("Nobody") or drifts inertly without executing its RivalAI behavior profile.
- **Fix**:
  1. Ensure the prefab contains at least one intact Remote Control block.
  2. If the prefab has multiple Remote Controls, MES attaches the behavior to the one flagged **Main Remote Control** in the prefab, otherwise the first one it finds (`BehaviorBuilder.cs`). To pick one by name, set `[ApplyBehaviorToNamedBlock:<CustomName>]` in the `[MES Manipulation]` profile.
  3. Ensure ownership is properly assigned via `[FactionOwner:<FactionTag>]` (Spawn Conditions, or inline in the `[Modular Encounters SpawnGroup]` Description).

### 9. Grid Sets Waypoints Properly But Refuses to Tilt Up or Down (Pitch Lock)
- **Cause**:
  1. `[LevelWithGravityWhenIdle:true]` state bleed: In `FighterPlane`, `Strike`, `Sniper`, and `HorseFighter`, entering idle sets `State.UseFlyLevelWithGravityIdle = true`. Because `EngageTarget` omits the idle parameter when calling `ActivateAutoPilot()`, the flag never resets, permanently latching `NewAutoPilotMode.LevelWithGravity` onto combat runs.
  2. `[FlyLevelWithGravity:true]`: Actively forces `LevelWithGravity` across all flight modes in all subclasses.
- **Result**: In `RotationSystem.cs:187`, `LevelWithGravity` forces gyro pitch to align solely with the planetary horizon, completely bypassing `directionToTarget`. The craft yaws toward waypoints but cannot dive to fire fixed guns or pitch up to climb toward breakaway waypoints.
- **Fix**: In the `[RivalAI Autopilot]` profile, explicitly disable both tags:
  ```xml
  [FlyLevelWithGravity:false]
  [LevelWithGravityWhenIdle:false]
  ```

### 10. NPC Reverses Into Space at Max Thrust / Overshoots Waypoints and Swings Back
- **Before MES 2.75.00 (runaway into space)**: `CalculateDirectForwardThrust` compared the unsigned `velocity.Length()` with `MaxSpeed`. A grid moving backwards faster than `MaxSpeed` (a rover rolling back downhill, or an aircraft facing its waypoint while drifting away with `MaxVelocityAngleForSpeedControl` above 90) showed `Brake To Desired Speed` in `/MES.IGGB`, fired reverse thrust and accelerated away indefinitely. Fixed in 2.75.00 (MES PR #402): it now uses the forward component of velocity, so a grid moving backwards gets forward thrust. Grids missing thruster directions no longer run away (field-observed).
- **2.75.00+ (overshoot and swing back, bounded)**: no reverse thrusters means `CalculateStoppingDistance()` is `0`, so the grid keeps full thrust until `WaypointTolerance`, coasts through the waypoint, turns around and comes back.
- **Fix**:
  1. `MaxVelocityAngleForSpeedControl:180` on 2.75.00+ (at most 90 on older builds); see [aircraft_behaviors_and_tuning.md](aircraft_behaviors_and_tuning.md) section 1.
  2. Add reverse thrusters so it can brake; see [behaviors_and_autopilot.md](behaviors_and_autopilot.md) §6A for what each direction does. On builds before 2.75.00, give it all six directions.
  3. For atmospheric aircraft with forward-only thrust, switch behavior subclass to `FighterPlane` (which uses velocity-aligned climbing breakaway without braking).
  3. For thrust-driven rovers, see [behaviors_and_autopilot.md §6.C](file:///c:/Users/blayl/source/repos/se-dev-mes/references/behaviors_and_autopilot.md#c-thrust-driven-rovers--ground-vehicles-best-practices--pitfalls-hard--soft) for the complete rover setup (`[UseSurfaceHoverThrustMode:true]`, `[FlyLevelWithGravity:false]`, and matching `[IdealPlanetAltitude]` to Remote Control height).

### 11. Rover NPC Stalls on Hills, Lifts Wheels, or Backflips Into Sky
- **Cause**:
  1. **Hill Stalling** (fly-level on only): with `FlyLevelWithGravity` or `LevelWithGravityWhenIdle` on, MES uses its hover thrust routine, which cuts forward thrust when tilted more than `HoverUpAngle` (default 10°). With both off this check never runs.
  2. **Wheel Lifting**: `[FlyLevelWithGravity:true]` forces chassis perpendicular to planetary gravity rather than terrain slope, lifting downhill/uphill wheels off the ground.
  3. **Backflipping on Turns**: with the waypoint behind, yaw and pitch both ask for the full rate, and a pitch multiplier anywhere near yaw makes the rover flip toward it instead of turning.
  4. **Sky Evasion**: Voxel collision raycasts detect ground in all directions except UP, commanding climb evasion into space.
- **Fix**: Apply the golden rover autopilot profile from [behaviors_and_autopilot.md §6.C](file:///c:/Users/blayl/source/repos/se-dev-mes/references/behaviors_and_autopilot.md#c-thrust-driven-rovers--ground-vehicles-best-practices--pitfalls-hard--soft):
  ```xml
  [UseSurfaceHoverThrustMode:true]
  [FlyLevelWithGravity:false]
  [LevelWithGravityWhenIdle:false]
  [IdealPlanetAltitude:<rc_block_height>]
  [HoverPathStepDistance:50]
  [WaypointTolerance:15]
  [RotationMultiplierPitch:0.1]
  [RotationMultiplierYaw:1.5]
  [RotationMultiplierRoll:1.0]
  [UseAircraftFlightModel:true]
  [MaxRotationStep:0.5]
  [LimitRotationSpeed:false]
  [MaxRotationMagnitude:1]
  [UseVelocityCollisionEvasion:false]
  ```
  If it still can't pivot against wheel friction, see §6C.5 of the same file (fix the gyro ramp before lowering friction).

### 12. Spawn Group Never Spawns / Silent Rejection ("Could Not Get Valid NPC Faction")
- **Cause**: The faction tag specified in `[FactionOwner]`, `[FactionOverride]`, or `[SpawnFactionTags]` does not exist in the world session (due to a typo, e.g. `SPTR` instead of `SPRT`, or because the mod containing `Factions.sbc` is missing or threw an XML deserialization error).
- **Result**: In `SpawnConditions.cs:2144`, `MyAPIGateway.Session.Factions.TryGetFactionByTag()` returns `null`. `ValidNpcFactions()` returns an empty list (`Count == 0`). In `SpawnGroupManager.cs:309`, the spawn group is skipped with `continue;`, permanently locking its natural and admin force-spawn rate to **0%** with no in-game warning or crash.
- **Log Diagnostic**: Search `SpaceEngineers.log` or spawner debug logs for:
  ```text
     - Could Not Get Valid NPC Faction.
  ```
- **Fix**:
  1. Verify the exact spelling of `[FactionOwner:<Tag>]` in `[MES Spawn Conditions]` and `[FactionOverride:<Tag>]` in `[MES Spawn Group]`.
  2. If using custom factions, verify that the defining `Factions.sbc` is loaded in the active world save and contains `<Tag>...</Tag>`.
  3. For unowned derelicts or neutral stations, use the reserved keyword `[FactionOwner:Nobody]`.
  4. Run `powershell -ExecutionPolicy Bypass -File scripts/audit_mes_tags.ps1` to detect undefined faction tags automatically.

### 13. `MES Behavior / Error: <Profile>: Could not parse tag '[GridDestructible:true]' (expected Yes, No or Ignore)`
- **Cause**: A Yes/No/Ignore (`CheckEnum`) tag was given another value. Since MES 2.74.04 this parser logs to the game log at load (always, no debug flag needed); before, the value was ignored silently. Affects `GridEditable`, `SubGridsEditable`, `GridDestructible`, `SubGridsDestructible` (RivalAI Action) and `IsStatic` (RivalAI Target).
- **Fix**: Use `Yes`, `No` or `Ignore` (case-sensitive). `scripts/audit_unknown_tags.py` catches this before load.

### 14. Zone / Known Player Location changes do nothing
- **Log lines** (`/MES.SpawnDebug.Zone.true`): `KnownPlayerLocation Not Created At ...: Duration Must Be Greater Than 0`; `Zone [<name>] At [<coords>] Has Been Removed Because its Timer Expired`.
- **Checklist**: MES ≥ 2.74.04 (zone custom bool/counter actions were no-ops before); `[ZoneName:]`/`[ZoneNames:]` equals the zone's `[PublicName:]`, not `[Name:]`; the zone is `[Persistent:true]`; `[ZoneRadiusChangeType(s):]`/`[ZoneCustomCounterChangeType:]` use `Set`/`Add`/`Subtract`/`Multiply`/`Divide`; `[KnownPlayerAreaTimer:]` > 0. Details: [`events_and_zones.md`](events_and_zones.md) §4 rules 2, 6, 7.

### 15. NPCs treated as players (wrong targets, `[Owners:NPC]` never matches) on MES 2.73.07-2.74.04; offline players treated as NPCs through 2.74.05
- **Cause**: `FactionHelper.IsIdentityNPC` returned `false` for any identity without an **online** `IMyPlayer` (`MyAPIGateway.Players.TryGetIdentityId` only searches connected players), which is every normal NPC faction identity. Effects: NPC owners classified as `Player` by the target `Owner` filter (`EntityEvaluator.GetOwnersFromList`), NPC-vs-player relations skipped the reputation lookup (`GetRelationBetweenIdentities`), `[CheckIfDamagerIsNpc:true]` never passed, and spawn-time NPC store setup did not fund the owner for inserted orders. **Fixed in MES 2.74.05** (#375): no Steam id, or an online bot, counts as NPC.
- **[HARD] Fixed in 2.75.00 (developed as 2.74.06 dev, commits `2361acf`, `13bcb1d`, `cb6f3b0`, 2026-10-04 to 10-09; patch note "Offline players being considered NPCs")**: `FactionHelper.IsIdentityNPC`/`IsIdentityPlayer` were rewritten to classify by online `IMyPlayer` + Steam id: a Steam id with no online player is an **offline player**, a bot with a Steam id is a vanilla bot (NPC), a non-bot with no Steam id is an AiEnabled bot (NPC), and an identity with neither is an NPC only if it was in the session's `NonPlayerIdentities` list. The ad-hoc `IsBot` / `SteamUserId <= 0` / `TryGetSteamId` checks in target selection, spawn conditions, relations, known player locations, chat recipients, the shield manager, NPC thrusters and ammo refill were switched to these two helpers (other code, e.g. `GridCleanup`, still uses `OwnershipHelper.IsNPC`). Re-check the effects below with `/MES.Info.GetActiveNpcs` on that build.
  - **[HARD] Startup order, 2.74.06 dev through 2.75.01 (fixed in MES 2.75.02, `814e6fb`, PR #406)**: `FactionHelper.Setup()` ran after `EntityWatcher` had scanned the grids already in the world, so every grid loaded from a save was checked against an empty NPC list. **Fails as**: after a world reload or server restart, existing NPC ships with thrust restrictions (`[RestrictNpcAtmoThrust:true]` etc.) have every thruster switched off (`NpcThrusterLogic` treats the owner as a player); newly spawned ships are fine. Fix: an MES build with `814e6fb`; on older builds the affected ships stay dead until they are despawned and respawned.
  - **[SOFT] Residual gap (read from `FactionHelper.Setup`, not observed)**: the NPC list is read **once** from the session checkpoint at load, so an NPC identity created later in the session, with no online player and no Steam id, matches neither helper.
- **[HARD] Through 2.74.05 (since 2.73.07, MES #379)**: `IsIdentityPlayer` also requires an online player, so an **offline** player is not a player to MES. `GetGridOwnerships` classifies grids owned by offline players as `NpcMajority`/`NpcMinority`, and caches the result until the grid's ownership changes (`GridEntity.OwnershipChange`); logging in does not recheck it.
  - At world load no one is connected (Keen's `LoadPlayerInternal` creates no `MyPlayer` for disconnected players), so `Tasks/NewGrid.cs` gives every loaded player grid blank `NpcData` (`SpawnType OtherNPC`, `SpawnedByMES` false), adds it to `NpcManager.ActiveNpcs`, and saves that `NpcData` into the grid's storage (`ProcessTertiaryAttributes` → `Update()`). The storage entry stays after the grid is later reclassified.
  - With `UseMaxNpcGrids` on, those grids count toward `MaxGlobalNpcGrids` (`SpawnRequest.cs:288`) and can block all spawns.
  - Cleanup skips them only while the OtherNPC config keeps `OnlyCleanNpcsFromMes` at its default `true`.
  - `[CheckIfDamagerIsPlayer:]`, `[CheckIfTargetIsPlayerOwned:]` and `[CheckIfTargetIsNpcOwned:]` misreport offline owners.
  - Check with `/MES.Info.GetActiveNpcs` (copies to clipboard): player grids listed under `Npc Majority`.

### 16. `System.Xml.XmlException: Root element is missing` (world or server will not load)
- **Cause**: an `.sbc` anywhere under the mod's `Data/` folder is **empty (0 bytes) or whitespace only**. Typical sources: an editor or agent tool that truncated the file, a failed save, or a placeholder created and never filled (seen in GVK: a 0-byte `GVK-Test-TargetFar-SpawnCondition.sbc`).
- **[HARD] What Keen does** (SE 1.210.014, `MyDefinitionManager.GetDefinitionBuilders`): every mod `.sbc` is opened with `CheckPrefabs`, whose `XmlReader.Read()` throws on an empty file. The catch writes `MOD SKIPPED, Cannot load definition file` with the exception to the definition errors, queues the exception, and after all files are read rethrows the queue as an `AggregateException`. `LoadData` does not catch it, so the whole world load aborts (dedicated server: startup fails), not just that mod.
- **Find it**: the log line names the mod but not always the file. Search the mod for empty files:
  ```powershell
  Get-ChildItem -Path "Data" -Filter *.sbc -Recurse | Where-Object { $_.Length -eq 0 -or -not (Get-Content $_.FullName -Raw).Trim() }
  ```
  `scripts/audit_sbc.ps1` reports empty and whitespace-only files (prefab folders included).
- **Fix**: delete the file, or restore it from git (`git checkout -- <file>`). Never leave a placeholder `.sbc`; a file that should define nothing still needs `<?xml version="1.0"?><Definitions xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema"></Definitions>`.

### 17. NPC ship with 12 or more grids only partly despawns (`Attempted Despawn 10 Times. Aborting Process.`)
- **Symptom**: after a behavior despawn, `[ForceDespawn:true]`, spawner cleanup or `/MES.Debug.DeleteGrid` / `RemoveAllNpcs`, the main grid and some wheels, rotor or piston heads stay in the world. Open as MeridiusIX/Modular-Encounters-Systems#412 (checked against `bc71965`).
- **Log** (`/MES.SpawnDebug.CleanUp.true`): eleven `Grid is Closed.` lines, then `<grid> Attempted Despawn 10 Times. Aborting Process.` for every grid still queued.
- **[HARD] Cause**: `Cleaning.RemoveGrid` queues the grid and all its linked grids. `Tasks/GridCleanup.cs` removes them one per run, and before each one adds 1 to `grid.Npc.DespawnAttempts`, skipping the grid once the count is above 10. Grids spawned together in this session share one NpcData object (`GridEntity.cs`, looked up by `UniqueSpawnIdentifier` in `NpcManager.SpawnedNpcData`), so the whole ship shares one counter: 11 grids go, the rest are dropped. Seen in GVK on a 13-grid land cargo ship (main grid and 12 wheels); the shared object was confirmed in play by the ship's `DespawnMES` triggers firing when its first wheel was removed. The limit dates from 2021 (`6d5ed75`).
- **[SOFT] After a world reload** each grid reads its own copy of the NpcData from its storage, so the counter should no longer be shared for ships loaded from a save. `DespawnAttempts` is saved (`[ProtoMember(18)]`), though, so a leftover saved after a failed despawn may still start above 10. Not tested.
- **Find affected prefabs**: count the `<CubeGrid>` elements per prefab; 12 or more is affected (`scripts/audit_prefabs.ps1` warns). Stations count too: a static base with turrets on rotors is despawned the same way.
- **Workaround until fixed**: keep NPC prefabs at 11 grids or fewer (merge or remove subgrids, use fewer wheels). MES cannot remove the leftovers either: `/MES.Debug.DeleteGrid` goes through the same cleanup and hits the same spent counter. Delete them as an admin (Space Master, Ctrl+X).

---

## 5. Sim-Speed Health & Anti-Clang Physics Mitigations

### A. Voxel Phasing & Solver Saturation
- **The Problem**: High-speed aircraft or rovers crashing into terrain meshes can tunnel past the surface voxel boundary, trapping rigid bodies in continuous Havok collision solver loops and dropping server sim-speed from 1.0 to 0.2.
- **The Solution**:
  1. Disabled aircraft grids should be force-despawned immediately on compromise (`[Type:Compromised]` -> `[ForceDespawn:true]`).
  2. Rovers operating near voxels must maintain `[MinimumPlanetAltitude:15]` or higher to prevent chassis collision clipping.

### B. Raycasting & Trigger Throttling
- Non-urgent distance or condition checks should never run on every frame. Use stepped cooldown intervals (`[MinCooldownMs:5000]`, `[MaxCooldownMs:5001]`) rather than 100ms loops.
- Use `[MatchSenderReceiverOwners:true]` in command profiles to prevent grid-to-grid broadcasts from flooding all network entities.

---

## 6. Field Notes [SOFT]

Observed on live servers, not yet checked against the MES code. Re-test after MES updates.

- **Crashes from razing:**
  - Don't raze blocks that can sit on subgrids.
  - Don't `RazeBlocks` the RivalAI Remote Control: `UpdateShape()` can crash if the block has split from its parent grid.
  - Don't run `GenerateExplosion` and a raze on the same block (for example the RivalAI Remote) at the same time.
- **Static encounter reset:** `[ResetThisStaticEncounter:true]` with `[ForceDespawn:true]` removes a static encounter and lets it respawn (not on the wiki).
- **Particles:** can be played from actions much like sounds (not on the wiki).
- **Climbing too steeply:** an `IdealPlanetAltitude` far above `MinimumPlanetAltitude` makes aircraft climb sharply and spoils their angle of attack.
- **Aim:** RivalAI aims poorly with fixed weapons. Where accuracy matters, Keen's AI blocks do better than the RivalAI autopilot.
- **Debris cleanup:** `[IgnoreCleanupRules:true]` on NPCs, with aggressive MES CleanUp settings, helps clear debris that has no active RivalAI block.
