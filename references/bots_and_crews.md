# NPC Bots & Crews Reference

Bots on MES encounters: Keen's combat bots (the Warfare 3 bots, SE 1.211) spawned through MES `[MES Bot Spawn]` profiles, Keen's own prefab crews, AiEnabled bots, and the despawn rules that apply to all of them.

> [!IMPORTANT]
> **Version.** MES support for Keen's bots is on upstream `master` after 2.75.03 (commits from 2026-11-13 on). The Workshop still runs 2.75.03 as of 2026-11-21. On 2.75.03 and older, `[MES Bot Spawn]` spawns AiEnabled bots only (§8) and `[UseAiEnabled:]` defaults to `true`. The tag cache follows the installed MES, so `query_mes_tags.py` and `audit_unknown_tags.py` know the tags in §3-§5 only once the installed MES has the bot code (then run `Update-MesSkill.ps1` and remove the `unreleased` fence markers, which make the audit list those tags as notes). MES line numbers are for `master` at `88ebcf0`; game references are SE 1.211.018 (the 2026-11-20 patch; the bot code is the same as in 1.211.017).

---

## 1. Keen's Bots (Game Side)

**[HARD]** From `IMyNPCSpawnerSessionComponent` and `MyBotAnchorComponent.cs`:

- **Squads**: a bot spawned with a grid joins that grid's squad. Squad members share alerts from damage to the grid, hits on any member and gunshots near the grid, and stay leashed to the grid. A bot spawned without a grid reacts only to hits on itself. One squad per grid; all its bots share the first bot's faction.
- **Behavior** is the bot definition's behavior tree. No ModAPI call (so no MES tag) can send a bot somewhere, pick its target or change its behavior. MES can only spawn bots, seat or unseat them, and delete them.
- **Setup** per bot: a weapons container (a `ContainerTypeDefinition` such as `NPCWeaponsContainerType`), a chat message set (`NpcChatMessageSetDefinition`) and loot (the faction's `BotLootContainerType` unless overridden).
- **Keen's own prefab crews**: the prefab or spawn-group prefab fields `MinNPCCount`/`MaxNPCCount`, `NPCBotSubtypes`, `NPCWeaponsContainerType`, `NPCChatMessageSet`, `NPCSpawnBlocksOverride`, `NPCSpawnPointsOverride` and `NPCHealth` create an "encounter crew" when the spawn group spawns. MES raises the same spawn event for its own spawns (`PrefabSpawner.cs:367`, already in 2.75.03), so these fields crew MES encounters too. MES does not link those bots to the grid: `[RemoveBotsFromGrid:]`, `[EjectBotsFromSeats:]` and `[CheckBotsRemaining:]` never see them, and Keen refuses `[AddBotsToGrid:]` on a grid that already has an encounter crew.

---

## 2. What Removes a Bot

| Cause | When | Source |
| :--- | :--- | :--- |
| Keen's distance sweep | Every 120 s: every bot more than 400 m from a human player who controls a character or a ship. Both values are hard-coded, and there is no exception for ModAPI or MES bots. A bot in a cockpit or seat is deleted with the others; one in a cryo chamber keeps its body but loses its player and AI. | `MyEnvironmentBotSpawningSystem.cs:20,26,112`, `MyPlayerCollection.cs:1756` **[HARD]** |
| Keen's encounter crew (§1) | No player within the encounter despawn distance (600 m default): the crew is despawned. | `MyGridBotPopulator.TickAnchor` **[HARD]** |
| MES grid cleanup | MES despawns the grid: its MES bots are deleted first. | `GridCleanup.cs:128` **[HARD]** |
| `[RemoveBotsFromGrid:true]` | The action runs (§5). | `ActionSystem.cs:2137` **[HARD]** |

> [!CAUTION]
> **[HARD] MES crews despawn by distance.** Keen's `SpawnBot` comment ("never despawns by distance") and the MES bot primer say these bots persist away from players. That holds for the squad, which never despawns anything, but the separate wildlife sweep above still deletes them. Modders have seen it in game with bots spawned through the ModAPI; an MES crew has not been tested in game yet. Keen had told the MES maintainer that these bots do not despawn by distance, and as of 2026-11-21 the maintainer is asking Keen whether a game patch will change it.
> - A crew on an encounter with no player within 400 m can be gone within 2 minutes of spawning.
> - MES then drops the deleted bots from the grid, so `[CheckBotsRemaining:]` counts 0 and a "crew wiped out" trigger fires without a fight. Suggestion: pair that trigger with `[Type:PlayerNear]` or a damage trigger, or add the crew from a `PlayerNear` trigger instead of at spawn.

---

## 3. Bot Spawn Profile (`[MES Bot Spawn]`)

```xml unreleased
<EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
  <Id>
    <TypeId>Inventory</TypeId>
    <SubtypeId>ModPrefix-BotSpawn-Guard</SubtypeId>
  </Id>
  <Description>
    [MES Bot Spawn]
    [BotType:HumanoidBot/CombatAstronaut]
    [BotFactionTag:{Faction}]
    [SpawnBlocks:MyObjectBuilder_CryoChamber/LargeBlockCryoChamber]
    [SpawnSeated:true]
    [Tags:Guards]
  </Description>
</EntityComponent>
```

| Tag | Default | Notes **[HARD]** (`BotSpawnProfile.cs`, `BotSpawner.cs`) |
| :--- | :--- | :--- |
| `[UseAiEnabled:]` | `false` (was `true` up to 2.75.03) | `true` takes the AiEnabled path (§8). AiEnabled profiles that relied on the old default need `[UseAiEnabled:true]`. |
| `[BotType:]` | none | Bot definition ID, `HumanoidBot/CombatAstronaut` or with the `MyObjectBuilder_` prefix (both parse). |
| `[BotFactionTag:]` | none | Required: a faction tag that exists in the world, or the action logs `Could not find faction with tag` and spawns nothing. `{Faction}` resolves. Every bot on one grid must share a faction (Keen's squad rule). |
| `[BotDisplayName:]` | random `CharacterName` | |
| `[WeaponsContainerId:]` | the definition's `StartingItem` | `ContainerTypeDefinition` subtype. |
| `[LootContainerId:]` | the faction's loot | `ContainerTypeDefinition` subtype. |
| `[ChatMessageSetId:]` | the definition's set | `NpcChatMessageSetDefinition` subtype. |
| `[SpawnBlocks:]` | none | Block IDs **with the `MyObjectBuilder_` prefix**, e.g. `MyObjectBuilder_Cockpit/LargeBlockCockpitSeat`. MES compares the text with the block's full ID string (`ActionSystem.cs:2074`), so `Cockpit/LargeBlockCockpitSeat` never matches. |
| `[SpawnSeated:]` | `true` | See §4. |
| `[Color:]` | unset | Suit RGB, 0-255: `[Color:{X:200 Y:30 Z:30}]`. |
| `[AssetOverrideSets:]` | faction skin | Skin set names from `SkinSetEnum` (`Soldier`, `Hazmat`, `Scavenger`, ...). One name per tag line; repeat the tag for more, and MES picks one at random. A comma list in one tag parses as a combined enum value and gives the wrong skin or none. `FactionDefault` adds nothing. |
| `[Tags:]` | none | Labels for the §5 filters, merged with the action's `[BotTags:]`. |

---

## 4. Spawning a Crew (`[AddBotsToGrid:true]`)

A RivalAI Action only. Event Actions cannot spawn bots (there is no grid to tie the squad to), and spawn-group bots are broken on `master` (§7).

```
[AddBotsToGrid:true]
[BotSpawnProfileNames:ModPrefix-BotSpawn-Guard]
[BotCount:3]
[BotTags:Guards]
```

**[HARD]** (`ActionSystem.cs:2047`, `BotSpawner.cs:210-340`):
- **One profile per run**: MES picks one name from `[BotSpawnProfileNames:]` and spawns all `[BotCount:]` bots from it.
- **Placement**: blocks on the grid matching the profile's `[SpawnBlocks:]`, or the action's `[BotSpawnBlockOverrides:]` in their place (`[SpawnBlockOverrides:]`, as the MES bot primer writes it, is not parsed). With no matching block, `[BotSpawnPointOverrides:{X:0 Y:1 Z:-2}]` gives positions relative to the Remote Control (comma list or repeated tags). With neither, nothing spawns.
- **`[SpawnSeated:true]` (default)**: only working, unoccupied seats count (cockpits, seats, cryo chambers). Other spawn blocks are skipped, so once the seats are full the remaining bots do not spawn (`No valid SpawnBlocks on grid` in the spawn log). Match `[BotCount:]` to the seats. Bots are seated one tick after they spawn.
- **`[SpawnSeated:false]`**: seats are skipped; each bot appears at the center of a non-seat spawn block, facing the Remote Control's backward direction, with no gravity correction.
- **Keen's refusals** go to the game log as `SpawnBot: '<type>' not spawned; ...`: the grid already has an encounter crew, the squad has living bots of another faction, the bot limit is reached, or the bot type or faction is unknown.
- `[OnlySpawnBotsInPressurizedRooms:]` applies to AiEnabled bots only.

---

## 5. Managing Crews

**[HARD]** (`ActionSystem.cs`, `ConditionProfile.cs`, `NpcData.cs:1209`):
- `[RemoveBotsFromGrid:true]` deletes the grid's MES bots; `[EjectBotsFromSeats:true]` makes the seated ones stand up. With `[BotTags:]`, only bots carrying one of those tags. The same `[BotTags:]` also labels bots that `[AddBotsToGrid:]` spawns, and in one action the add runs first, so keep adding and removing in separate actions.
- `[CheckBotsRemaining:true]` with `[MaxRemainingBots:]` and/or `[MinRemainingBots:]` (either one satisfied passes) counts the grid's MES bots that still exist. **Always set `[CheckBotTags:]`**: the count includes only bots with one of those tags, so without it the count is always 0. `[MaxRemainingBots:0]` is then true at once, and `[MinRemainingBots:1]` is never true.
- `[IsTargetBot:true]` is true when the current target is a bot. On `master`, `[IsTargetGrid:true]` matches only grids and blocks; it used to match anything that was not a player.
- `[Target:]` in `[RivalAI Target]` gains `Bot`, `PlayerAndBot`, `PlayerAndBotAndGrid` and `PlayerAndBotAndBlock`. A bot target candidate is any bot MES tracks within `[MaxDistance:]`, Keen crews and other mods' bots included (`TargetingSystem.cs:525`).
- WeaponCore homing weapons whose threats include Characters accept a bot target (`CoreWeapon.cs`).
- MES bots are saved with the grid's NPC data (`NpcData.cs:447`) and relinked on load.

---

## 6. Debugging

- `/MES.Info.GetActiveBots` copies every bot MES tracks to the clipboard, grouped by grid: name, faction, profile, tags, alive. Bots MES did not spawn (Keen crews, other mods) are listed under "Tracked Non-MES Bots".
- `/MES.Info.GetGridBehavior` and `/MES.Info.GetGridData` list the grid's MES bots under `Bots:`.
- Spawn errors go to the spawn log (`/MES.SpawnDebug.Spawning.true`, copied with `/MES.IGLSD.Spawning`). Action errors (unknown profile, missing faction, no spawn blocks) go to `/MES.BehaviorDebug.Action.true` (`/MES.IGLBD.Action`). Keen's refusals are only in the game log.
- To test the distance sweep, spawn the crew, check `/MES.Info.GetActiveBots`, move more than 400 m away for over 2 minutes, come back and check again. The sweep measures from the character or ship you control, so moving only the spectator camera does not count.

---

## 7. Known Issues (`master` at `88ebcf0`)

- **Spawn-group bots never spawn.** `[CreatureSpawn:true]` + `[BotProfiles:]` calls the new spawn path with no spawn blocks or points (`BotSpawner.cs:92`), so it logs `No SpawnBlocks nor SpawnPoints defined` and spawns nothing, AiEnabled profiles included (they worked on 2.75.03). Spawn groups using `[CreatureIds:]` are unaffected.
- **The distance sweep** (§2) deletes MES crews away from players. This is game code, not MES; the MES maintainer is waiting on Keen (2026-11-21).

---

## 8. AiEnabled Bots

With the **AiEnabled** mod loaded, `[UseAiEnabled:true]` profiles spawn AiEnabled bots:

```xml
<Description>
  [MES Bot Spawn]
  [UseAiEnabled:true]
  [BotType:<AiEnabled bot subtype>]
  [BotBehavior:Soldier]
  [BotDisplayName:Security]
  [CanUseSeats:true]
  [CanDamageGrids:false]
</Description>
```

1. **Crew inside a live grid (RivalAI Action)**: `[AddBotsToGrid:true]` + `[BotSpawnProfileNames:]` + `[BotCount:]`, optionally `[OnlySpawnBotsInPressurizedRooms:true]`. AiEnabled picks free spots on the grid itself; `[SpawnBlocks:]` and `[SpawnSeated:]` do not apply.
2. **Standalone ground spawns (Spawn Conditions)**: `[CreatureSpawn:true]` + `[BotProfiles:]` + `[MinCreatureCount:]`/`[MaxCreatureCount:]` + `[MinCreatureDistance:]`/`[MaxCreatureDistance:]`. On 2.75.03 MES picks one listed profile at random per bot (`BotSpawner.cs:65`); broken on `master` (§7).

- AiEnabled bots need navigable corridors or walkable surfaces on the grid.
- Up to 2.75.03 `[UseAiEnabled:]` defaults to `true`; without the AiEnabled mod loaded, only vanilla creature types spawn.
- `[BotBehavior:]` is the AiEnabled role and must be set: the default `Default` is not a role, and AiEnabled refuses the bot. Roles: [`third_party_integrations.md`](third_party_integrations.md) §3.
