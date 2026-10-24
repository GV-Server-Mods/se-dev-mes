# In-Game Testing & Debugging Procedures for MES Encounters

How to test an NPC mod built on MES, and how an agent writes a test procedure the mod author can follow in game. Command details are in `diagnostics_and_troubleshooting.md` §2; error signatures in its §4.

**Verified against**: MES `bc71965` (2.75.02), `Sync/ChatMessage.cs`, `Logging/LoggerTools.cs`, `Spawning/SpawnRequest.cs`, `Spawning/SpawnConditions.cs`. **[HARD]** = read in source. **[SOFT]** = field practice.

---

## 1. Rules for writing a test procedure

Work down this ladder. Only go to the next rung when the current one cannot explain the problem.

1. **Visual checks** with admin debug commands (§3).
2. **Debug chat messages** added to the profiles under test (§4).
3. **Logs** (§5). Second to last: logs are long, slow to read, and need the tester to copy buffers out.
4. **Debug lines injected into the local MES copy** (§6). Last resort, but valid: it has found real MES bugs.

Every procedure the agent writes must follow these rules:

- **Steps the tester can actually do**: chat commands, flying or walking to a spot, approaching, shooting or damaging the NPC, saving and reloading the world, editing the mod's `.sbc` files. **Never** ask them to paste text or scripts into a Remote Control or other block, edit a block's Custom Data, or run a programmable block to "inspect" MES.
- **Checks the tester can actually see**: how the grid moves, chat lines, `/MES.Debug.DrawPaths` lines, zone spheres, GPS markers, the clipboard text from `/MES.IGGB` and the other `/MES.Info.*` commands, and block states shown in the terminal (on/off, owner). **Never** ask them to look for HUD elements, markers or values that MES does not show to a player.
- **Exact commands, in order**, with where to stand, what to do, what to expect, and what each result means.
- **Spawn the NPC with MES, never from a blueprint or a pasted prefab.** A pasted grid does not go through the spawner, so it skips the spawn conditions, manipulation, faction ownership and the NPC data the behavior relies on; whatever it does says nothing about the real encounter.
- **One change per test cycle.** MES reads its profiles when the world loads, so after editing an `.sbc`: save, quit to the main menu, and load the world again (dedicated server: restart). After changing a prefab, delete its `.sbcB5` (`diagnostics_and_troubleshooting.md` §4.7).
- **Confirm the change is in the game before handing over a test.** A mod built from a project (MDK2, a deploy script) only reaches the game after a build; check the deployed copy in `%AppData%\SpaceEngineers\Mods\<mod>` for the new tag or profile, or a test runs on the old files. A local MES clone used as the mod is live without a build.
- **Clean up between runs**: `/MES.Debug.RemoveAllNpcs` removes every grid that is mostly NPC-owned and passes MES's basic cleanup checks (Keen economy stations are kept). `/MES.Debug.DeleteGrid` removes the one grid under your crosshair (within 10 km).

---

## 2. Make the test NPC spawnable on demand **[HARD]**

`/MES.Spawn.<Type>.<SpawnGroupName>` (or a shortcut below) spawns that one group at the tester's position. It runs as an **admin spawn** (`ChatMessage.ProcessSpawn` -> `SpawnRequest.CalculateSpawn(..., forceSpawn: false, adminSpawn: true, ...)`):

- It **skips** spawn timeouts and the global NPC cap (`MaxGlobalNpcGrids`).
- It **still checks** every other condition of the spawn group at the tester's position: spawn type, planet and altitude, threat, zones, faction, sandbox variables and the rest. Stand where a natural spawn would be allowed.
- The spawn group name is split on `.`, so a name containing a dot cannot be spawned this way.

**The spawn group needs a conditions profile with the matching spawn type**, or the debug log says `SpawnGroup SpawnType(s) Not Matched.` and nothing spawns (`SpawnConditions.SpawningTypeAllowedForGroup`):

| Command (shortcut) | Conditions tag that must be `true` |
| :--- | :--- |
| `/MES.Spawn.SpaceCargoShip` (`/MES.SSCS`) | `[SpaceCargoShip:true]` (`[LunarCargoShip:true]` near moons) |
| `/MES.Spawn.PlanetaryCargoShip` (`/MES.SPCS`) | `[AtmosphericCargoShip:true]` (`[GravityCargoShip:true]` for gravity without atmosphere). There is no `PlanetaryCargoShip` conditions tag. |
| `/MES.Spawn.PlanetaryInstallation` (`/MES.SPI`) | `[PlanetaryInstallation:true]` |
| `/MES.Spawn.RandomEncounter` (`/MES.SRE`) | `[SpaceRandomEncounter:true]` |
| `/MES.Spawn.BossEncounter` (`/MES.SBE`) | `[BossEncounterSpace:true]`, `[BossEncounterAtmo:true]` or `[BossEncounterAny:true]`, for where the tester stands |
| `/MES.Spawn.DroneEncounter` (`/MES.SDE`) | `[DroneEncounter:true]` |
| `/MES.Spawn.Creature` (`/MES.SC`) | `[CreatureSpawn:true]` |

- **No chat spawn for static encounters.** `/MES.SSE` is rewritten to `/MES.Spawn.StaticEncounter`, but `ProcessSpawn` has no `StaticEncounter` case, so it only answers `No Spawning Type From Chat`. Test a static encounter by flying to its coordinates; to respawn it, use `/MES.Debug.ResetThisStaticEncounters.<SpawnGroupName>` or `/MES.Debug.ResetStaticEncounters` (`diagnostics_and_troubleshooting.md` §2D).
- **NPCs normally spawned by something else** (a `[RivalAI Spawn]` profile, an event, a store purchase) still need a spawn type to be tested alone. Add a test-only conditions profile to the group, e.g. `[SpawnConditionsProfiles:MyGroup-Conditions,MyGroup-TestConditions]`, where the test profile sets the spawn type plus `[AdminSpawnOnly:true]` so it never passes for a natural spawn. Each conditions profile is checked on its own and the one that passes is the one used for the spawn (`spawning_and_conditions.md` §2, inline profiles; `/MES.IGGD` shows its `ConditionIndex`), so copy into the test profile every placement and faction tag the real profile uses (`[FactionOwner:]`, `[PlanetaryInstallationType:]`, ...).
- **Test files must never be empty.** A 0-byte `.sbc` stops the whole world from loading (`diagnostics_and_troubleshooting.md` §4.16). Run `scripts/audit_sbc.ps1` before loading. Remove the test profiles before release, or keep them `[AdminSpawnOnly:true]`.
- **Nothing spawned?** Check in this order: the chat reply (`No Spawning Type From Chat` = wrong type word); `/MES.GESAP` at the spot (lists the groups eligible here for natural spawns, so it also applies timeouts); then the spawn log (§5).

---

## 3. Visual checks first **[HARD]**

Look at the grid (crosshair on it, within 10 km) for the `/MES.Info.*` grid commands. Each copies its report to the clipboard; the tester pastes it to the agent.

| Question | Command | What to look for |
| :--- | :--- | :--- |
| Did the AI attach at all? | `/MES.IGGB` | `Grid Does Not Have Registered Behavior` means no behavior: check the Remote Control (`diagnostics_and_troubleshooting.md` §4.8), then the `BehaviorSetup` log. Otherwise read the behavior, subclass, mode and autopilot profile. |
| Which trigger state, which autopilot mode? | `/MES.IGGB` | Trigger list with cooldowns and use state; AutoPilot section with `Forward Thrust Mode` (`Brake To Desired Speed`, `Current Dist / Stop Dist`). |
| Where is it trying to go? | `/MES.Debug.DrawPaths` (toggle) | Green current waypoint, cyan offset (attack-run line-up, escort slot), magenta planet pathing, red/orange collision evasion. Singleplayer or the hosting machine. |
| Zones, KPLs | `/MES.Debug.ShowAllZones`, `/MES.Debug.ShowZone.<PublicName>` | Sphere and GPS for each active zone. Only one KPL is drawn at a time. |
| How was it spawned? | `/MES.IGGD` | The grid's NpcData: `SpawnType`, `SpawnGroupName`, `ConditionIndex` (which conditions profile was used, 0 = the spawn group's own Description), `BehaviorName`, `InitialFaction`, `DespawnAttempts`. |
| Can it spawn here? | `/MES.GESAP` | Eligible spawn groups at this position. |
| Threat score here | `/MES.GTS` | Compare with the group's threat conditions. |
| Which NPCs exist? | `/MES.Info.GetActiveNpcs` | Every NPC grid MES tracks, by ownership class. |

To **change** state for a test, use `/MES.Debug.ChangeBool.<Name>.<true|false>` and `/MES.Debug.ChangeCounter.<Name>.<Amount>` (adds, does not set) for sandbox variables, and `/MES.Debug.CreateKPL.<Faction>.<Radius>.<Minutes>.<MaxEncounters>.<MinThreat>` for a KPL at your position. Natural spawns blocked by a spawn timeout from earlier runs: `/MES.Debug.ClearTimeoutsAtPosition` (or `ClearAllTimeouts`).

---

## 4. Debug chat messages second **[HARD]**

Add a debug message to the profiles under test, so the chat shows each step as it happens.

- **RivalAI**: `[DebugMessage:<text>]` in a `[RivalAI Action]` (grid counters as `{CounterName}` and the usual tokens resolve). A trigger runs every action in its `[Actions:]` list by default (`[ActionExecution:All]`), so a separate debug action can be added to a trigger's list without editing its real action.
- **Events**: `[DebugChatMessage:<text>]` or `[DebugHudMessage:<text>]` in a `[MES Event Action]`.
- **Make the message say which step fired**: `[DebugMessage:STEP 3 patrol return | Kills {Kills}]`. One message per trigger in the chain shows where the chain stops.
- A trigger that never prints: its type check or a condition fails, or it is on cooldown, disabled, or used up (`[MaxActions:]`). Check it in `/MES.IGGB` before turning on logs.
- **Remove every debug tag before release** (`diagnostics_and_troubleshooting.md` §1C): they message every player on the server.

---

## 5. Logs second to last **[HARD]**

1. Pick the debug types for the symptom (`diagnostics_and_troubleshooting.md` §2A-B for the full list):

   | Symptom | Turn on |
   | :--- | :--- |
   | Does not spawn, wrong group or place | `/MES.SpawnDebug.SpawnGroup.true`, `/MES.SpawnDebug.Spawning.true` (zones: `.Zone`) |
   | Spawns without AI | `/MES.BehaviorDebug.BehaviorSetup.true` |
   | Trigger or action does not fire | `/MES.BehaviorDebug.Trigger.true`, `.Condition.true`, `.Action.true` |
   | Commands between grids | `/MES.BehaviorDebug.Command.true` |
   | Targets, weapons | `/MES.BehaviorDebug.TargetAcquisition.true`, `.TargetEvaluation.true`, `.Weapon.true` |
   | Despawn or cleanup | `/MES.BehaviorDebug.Despawn.true`, `/MES.SpawnDebug.CleanUp.true` |

2. Reproduce once, then copy each buffer you turned on: `/MES.IGLSD.<Type>` (spawn) and `/MES.IGLBD.<Type>` (behavior). The `<Type>` is required, and each type has its own buffer.
3. For long or intermittent problems, also send everything to the game log with `/MES.SpawnDebug.GameLog.true` / `/MES.BehaviorDebug.GameLog.true`, and point the agent at `%AppData%\SpaceEngineers\SpaceEngineers*.log` (dedicated server: the instance's `SpaceEngineersDedicated*.log`). Search it for the signatures in `diagnostics_and_troubleshooting.md` §4 and for `MOD SKIPPED`, `Exception`, `Could not parse tag`.
4. Turn every debug type off again (`.false`) after the test.
5. **Targeting logs don't name the grid doing the rating.** Each `Evaluating Target: X using profile P` line names the target and the profile; work out the rater from `P` (a faction copy of a profile, or an `-Override` profile for a forced target).
6. **To explain a relation result, read the save.** `scripts/save_relations.py <world>\Sandbox.sbc` prints the faction-to-faction relations (what turrets use) and each faction's members' reputation with every other faction (what MES uses for NPC-vs-NPC), from `<MyObjectBuilder_FactionRelation>` and `<MyObjectBuilder_PlayerFactionRelation>`. The save only changes when the world is saved.

---

## 6. Last resort: debug lines in the local MES copy **[HARD]**

Use this when the logs show the wrong result but not why, and the cause may be MES itself. Singleplayer test world only; never on a live server.

1. **Get the source as a local mod**: clone MES (MeridiusIX/Modular-Encounters-Systems) to `%AppData%\SpaceEngineers\Mods\Modular-Encounters-Systems`. In the test world's mod list, remove the Workshop MES and add the local one. Record the commit (`git -C <path> log -1 --oneline`) so findings can be quoted against it.
2. **Read the code path first** and put the line at the decision you doubt, printing its inputs (the condition values, the distance, the flag), not just "reached here".
3. **Write through MES's own loggers** so the line follows the debug switches:
   ```csharp
   BehaviorLogger.Write("[DBG] TargetFar: hasTarget=" + hasTarget + " dist=" + dist, BehaviorDebugEnum.Dev);
   SpawnLogger.Write("[DBG] conditions " + conditions.ProfileSubtypeId, SpawnerDebugEnum.Dev);
   ```
   then `/MES.BehaviorDebug.Dev.true` (or `/MES.SpawnDebug.Dev.true`) plus `GameLog`. `MyLog.Default.WriteLine("[DBG] ...")` always writes to the game log. Mod scripts compile as C# 6 against the ModAPI whitelist (see the `se-mod-performance` skill); a compile error is logged at world load and MES does not run at all.
4. **Reload the world** after each change (scripts compile at load), reproduce, and search the log for `[DBG]`.
5. **Revert when done**: `git -C <path> checkout -- .` (or `stash`), and switch the test world back to the Workshop MES. Never ship instrumented MES.
6. **Confirmed MES bug?** Use the `se-dev-mes-contributing` skill to report it upstream, and add the caveat to this skill.

---

## 7. Test checklists by feature **[SOFT]**

Each line: what to do, then what to check. Start every run with the spawn command from §2.

- **Spawn group**: spawn it; check placement, faction (`/MES.IGGD`), manipulation (block replacement, dereliction, loot). Then walk away past the despawn distance and check it despawns.
- **Behavior and triggers**: `/MES.IGGB` for the starting subclass; cause each event (approach, shoot, damage, lose target) and watch the debug messages from §4 fire in order.
- **Autopilot and aircraft**: `/MES.Debug.DrawPaths` on; watch one full patrol leg and one attack run; `/MES.IGGB` during an overshoot for `Forward Thrust Mode` (`aircraft_behaviors_and_tuning.md` §1 and §6).
- **Commands, parents and escorts**: spawn the parent, let it spawn or call its children; debug messages on the sender's and receiver's `CommandReceived` triggers; destroy the parent (`/MES.Debug.DeleteGrid`) and check the children's reaction.
- **Zones and KPLs**: `/MES.Debug.ShowAllZones` before and after the action that changes the zone; set the sandbox state with `/MES.Debug.ChangeBool` / `ChangeCounter` to test each branch.
- **Persistence**: save, reload, and repeat the checks above. Counters, KPLs, `ParentId` and trigger state must survive; NPC thrusters must still work (`diagnostics_and_troubleshooting.md` §15).
- **Despawn and cleanup**: trigger the despawn path the encounter uses (`[DespawnTypeFromSpawner:]`, `behaviors_and_autopilot.md` §9); check every subgrid is gone (wheels, rotors). A ship with 12 or more grids loses only its first 11 (MES #412, `diagnostics_and_troubleshooting.md` §4.17).
