# Grid Manipulation, Dereliction & AiEnabled Reference

Comprehensive reference for MES grid manipulation profiles, block replacement systems, weapon randomization, dereliction damage physics, and AiEnabled bot spawning.

---

## 1. Manipulation Profile Architecture (`[MES Manipulation]`)

Manipulation profiles modify NPC grids at the moment of spawning, before physics or AI initialize. Attach them to a spawn group with `[ManipulationProfiles:]` (or `[ManipulationGroups:]`); tags written directly in the `[Modular Encounters SpawnGroup]` Description are also parsed as its first Manipulation profile.

```xml
<EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
  <Id>
    <TypeId>Inventory</TypeId>
    <SubtypeId>ModPrefix-Manipulation-Standard</SubtypeId>
  </Id>
  <Description>
    [MES Manipulation]
    [UseBlockReplacerProfile:true]
    [BlockReplacerProfileNames:ModPrefix-BlockReplacement-Military]
    [RandomizeWeapons:true]
    [WeaponRandomizerTargetWhitelist:LargeGatlingTurret]
    [UseGridDereliction:true]
    [DerelictionProfiles:ModPrefix-Dereliction-Wreck]
    [ClearGridInventories:true]
  </Description>
</EntityComponent>
```

### Key Manipulation Capabilities:
- **Block Replacer**: `[UseBlockReplacer:true]` + `[ReplaceBlockOld:]`/`[ReplaceBlockNew:]` pairs (or `[ReplaceBlockReference:]`), or `[UseBlockReplacerProfile:true]` + `[BlockReplacerProfileNames:]` pointing at `[MES Block Replacement]` profiles. `[ConvertToHeavyArmor:true]` is a built-in replacement set.
  - **[HARD]** A replacement is skipped unless both blocks have the same `Size`, unless `[RelaxReplacedBlocksSize:true]` (`BlockReplacement.cs:90`). Profiles run in the order listed, so once one profile has replaced a block, a later profile matching the old subtype never sees it.
- **[HARD] RivalAI block:** with `[UseRivalAi:true]` + `[RivalAiReplaceRemoteControl:true]`, MES turns the grid's main (or first) Remote Control into a RivalAI control module (`BehaviorBuilder.cs:74-90`). Block replacement runs first (`PrefabManipulation.cs:374` before `:518`), so a replacer that turns a cockpit seat or AI block into `RivalAIRemoteControlLarge` also works. A grid with neither gets **no behavior** ("Following Behavior Could Not Be Applied"), silently.
- **Weapon Randomizer**: `[RandomizeWeapons:true]` (§2).
- **Dereliction**: `[UseGridDereliction:true]` + `[DerelictionProfiles:]` (§3). Without the gate, `PrefabManipulation.cs:672` skips dereliction entirely.
- **Inventory Control**: `[ClearGridInventories:true]`, ContainerType assignment (§6). Ammo/fuel top-up is a spawn-group feature (§5).
- **Hull Cosmetics**: `[RecolorGrid:true]` + `[ColorReferencePairs:]` (or `[RecolorOld:]`/`[RecolorNew:]`), `[ShiftBlockColorsHue:true]`, `[AssignGridSkin:]`, `[SkinRandomBlocks:true]` + `[SkinRandomBlocksTextures:]` + `[MinPercentageSkinRandomBlocks:]`/`[MaxPercentageSkinRandomBlocks:]`, `[ReskinTarget:]`/`[ReskinTexture:]`.
- **Thrust Restrictions**: `[ConfigureSpecialNpcThrusters:true]` with `[RestrictNpcIonThrust:]` / `[RestrictNpcAtmoThrust:]` / `[RestrictNpcHydroThrust:]` and per-type `ThrustForceMultiply` / `ThrustPowerMultiply` tags (e.g. `[NpcAtmoThrustForceMultiply:]`). MES has no thruster-type conversion tag.

---

## 2. Weapon Randomizer & Public Block Constraints

MES includes an automated weapon replacement pipeline that dynamically upgrades or randomizes turret and fixed-weapon arsenals:

- `[RandomizeWeapons:true]`: Master switch.
- `[WeaponRandomizerTargetWhitelist:<SubtypeId or TypeId/SubtypeId>]` / `[WeaponRandomizerTargetBlacklist:...]`: Which weapon blocks on the prefab may be replaced (`WeaponRandomizer.cs:969` matches either form).
- `[WeaponRandomizerWhitelist:...]` / `[WeaponRandomizerBlacklist:...]`: Which weapons may be installed as replacements.
- `[RandomWeaponChance:<int>]`, `[RandomWeaponSizeVariance:<int>]`, `[NonRandomWeaponNames:]` / `[NonRandomWeaponIds:]`.

### The `<Public>true</Public>` Requirement:
> [!CAUTION]
> **[HARD] Public Definition Gate**: In `WeaponRandomizer.cs` (lines 182–194), MES iterates block definitions in the game database and checks `if (!definition.Public)`.
> If a block definition has `<Public>false</Public>` in its SBC definition (very common for hidden `_NPC` weapon variants), MES **skips it** unless:
> 1. A `[MES Weapon Mod Rules]` profile specifies `[AllowIfNonPublic:true]`.
> 2. Or the SubtypeId is in `DefaultPublicBlocks`.
> Custom NPC weapons must have `<Public>true</Public>` in their SBC definition or an explicit weapon mod rule.

---

## 3. Dereliction & Damaged Block Rendering (`[MES Dereliction]`)

Dereliction transforms clean prefabs into battle-damaged, smoking, sparking ruins. Reference it from a Manipulation profile with `[UseGridDereliction:true]` + `[DerelictionProfiles:]`.

```xml
<EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
  <Id>
    <TypeId>Inventory</TypeId>
    <SubtypeId>ModPrefix-Dereliction-Wreck</SubtypeId>
  </Id>
  <Description>
    [MES Dereliction]
    [Blocks:MyObjectBuilder_CubeBlock/LargeBlockArmorBlock]
    [Blocks:MyObjectBuilder_CubeBlock/LargeBlockArmorSlope]
    [Chance:40]
    [UseSeparatePercentages:true]
    [MinIntegrityPercentage:20]
    [MaxIntegrityPercentage:65]
    [MinBuildPercentage:10]
    [MaxBuildPercentage:45]
  </Description>
</EntityComponent>
```

- **[HARD] `[Blocks:]` is required**: `DerelictionProfile.ProcessBlock()` (line 144) returns immediately for any block not in the `[Blocks:]` list. With `[MatchOnlyTypeId:true]`, a listed block's TypeId matches every subtype of that type. A profile without `[Blocks:]` does nothing.
- `[Chance:<0-100>]`: Per-block roll (default `100`).

### The Separate Percentages Rule:
> [!CAUTION]
> **[HARD] The Scaffolding Trap**: In `DerelictionProfile.cs` (lines 171–188), if `[UseSeparatePercentages:true]` is omitted (it defaults to `false`), MES rolls one value from `[MinPercentage:]`/`[MaxPercentage:]` and sets:
> `build = value; integrity = value;`
> In the Space Engineers engine, when `BuildPercentage == IntegrityPercentage`, a block renders as an **unfinished construction skeleton** rather than a damaged/smoking block!
> Furthermore, `MinIntegrityPercentage`, `MaxIntegrityPercentage`, `MinBuildPercentage`, and `MaxBuildPercentage` are completely ignored unless `[UseSeparatePercentages:true]` is explicitly declared.

---

## 4. Bot Spawning (AiEnabled Integration) (`[MES Bot Spawn]`)

MES integrates with the **AiEnabled** mod through `[MES Bot Spawn]` profiles. A bot profile describes one bot and is used by two different spawn paths:

```xml
<EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
  <Id>
    <TypeId>Inventory</TypeId>
    <SubtypeId>ModPrefix-BotSpawn-Soldier</SubtypeId>
  </Id>
  <Description>
    [MES Bot Spawn]
    [UseAiEnabled:true]
    [BotType:<AiEnabled bot subtype>]
    [BotBehavior:Default]
    [BotDisplayName:Security]
    [CanUseSeats:true]
    [CanDamageGrids:false]
  </Description>
</EntityComponent>
```

1. **Crew inside a live grid (RivalAI Action)**: `[AddBotsToGrid:true]` + `[BotSpawnProfileNames:ModPrefix-BotSpawn-Soldier]` + `[BotCount:<int>]`, optionally `[OnlySpawnBotsInPressurizedRooms:true]`.
2. **Standalone ground spawns (Spawn Conditions)**: `[CreatureSpawn:true]` + `[BotProfiles:<BotSpawnSubtypeId>]` + `[MinCreatureCount:]`/`[MaxCreatureCount:]` + `[MinCreatureDistance:]`/`[MaxCreatureDistance:]` (`BotSpawner.cs:65` picks one listed profile at random per bot).

### AiEnabled Integration Notes:
- **Grid Waypoints**: AiEnabled requires grids to have navigable corridors or walkable surfaces for bots to pathfind effectively.
- `[UseAiEnabled:]` defaults to `true`; without the AiEnabled mod loaded, only vanilla creature/bot types can spawn.

---

## 5. Replenishment (`[ReplenishSystems:]` + `[MES Replenishment]`)

Replenishment is a **spawn-group** feature: with `[ReplenishSystems:true]` in the `[Modular Encounters SpawnGroup]` Description, MES fills ammo, fuel and similar system inventories when the grid spawns (`NpcData.cs:762` → `InventoryHelper.ReplenishGridSystems`). `[ReplenishProfiles:]` (also on the spawn group) points at `[MES Replenishment]` profiles that cap or exclude items:

```xml
<EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
  <Id>
    <TypeId>Inventory</TypeId>
    <SubtypeId>ModPrefix-Replenish-Ammunition</SubtypeId>
  </Id>
  <Description>
    [MES Replenishment]
    [MaxItemId:MyObjectBuilder_AmmoMagazine/NATO_25x184mm]
    [MaxItemAmount:100]
    [RestrictedItems:MyObjectBuilder_AmmoMagazine/LargeRailgunAmmo]
  </Description>
</EntityComponent>
```

- `[MaxItemId:]` / `[MaxItemAmount:]` are paired lists (index-matched; extra entries are dropped).
- `[IgnoreGlobalReplenishProfiles:true]` on the spawn group skips server-wide profiles.
- Runtime top-up during combat is a different mechanism: `[UseAmmoReplenish:true]` + `[AmmoReplenishClipAmount:]` + `[MaxAmmoReplenishments:]` in `[RivalAI Weapons]`.

---

## 6. ContainerTypes, Loot Tables & Inventory Injections

ContainerTypes bridge vanilla Space Engineers inventory generation with MES spawning and RivalAI runtime actions.

### A. Vanilla Foundation (`ContainerTypes.sbc`)
In Space Engineers, loot tables are defined in `<TypeId>ContainerTypeDefinition</TypeId>` inside `ContainerTypes.sbc`:

```xml
<Definitions xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
  <ContainerTypes>
    <ContainerType CountMin="3" CountMax="4">
      <Id>
        <TypeId>ContainerTypeDefinition</TypeId>
        <SubtypeId>PersonalContainerSmall</SubtypeId>
      </Id>
      <Items>
        <Item AmountMin="1" AmountMax="5">
          <Frequency>1.0</Frequency>
          <Id>
            <TypeId>Ingot</TypeId>
            <SubtypeId>Uranium</SubtypeId>
          </Id>
        </Item>
        <Item AmountMin="1" AmountMax="10">
          <Frequency>1.0</Frequency>
          <Id>
            <TypeId>Ingot</TypeId>
            <SubtypeId>GVK_CUs</SubtypeId>
          </Id>
        </Item>
        <Item AmountMin="1" AmountMax="2">
          <Frequency>0.2</Frequency>
          <Id>
            <TypeId>Component</TypeId>
            <SubtypeId>GVK_TurboEncabulator</SubtypeId>
          </Id>
        </Item>
      </Items>
    </ContainerType>
  </ContainerTypes>
</Definitions>
```

- **`CountMin` / `CountMax`**: Governs how many distinct item types from `<Items>` are rolled for the inventory.
- **`<Frequency>`**: Relative probability weight for an item to be selected.
- **`<AmountMin>` / `<AmountMax>`**: Quantity rolled once an item is selected.
- **GVK Production Pattern**: Overriding vanilla subtypes like `PersonalContainerSmall` (used across Keen prefabs and drop pods) allows injecting server progression items (e.g. Uranium, CUs, RUs, Tech components) globally without editing dozens of prefab blueprints.

### B. MES Spawning Manipulation (`[MES Manipulation]`)
Manipulation profiles modify prefab inventories at spawn:

```xml
<EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
  <Id>
    <TypeId>Inventory</TypeId>
    <SubtypeId>ModPrefix-Manipulation-LootSetup</SubtypeId>
  </Id>
  <Description>
    [MES Manipulation]
    [ClearExistingContainerTypes:true]
    [AssignContainerTypesToAllCargo:PersonalContainerSmall]
    [UseContainerTypeAssignment:true]
    [ContainerTypeAssignBlockName:Cargo-Valuable]
    [ContainerTypeAssignSubtypeId:HighTierMilitaryLoot]
  </Description>
</EntityComponent>
```

- **`[AssignContainerTypesToAllCargo:<ContainerTypeId>]`**: Replaces the container type on all cargo blocks across the grid (randomly selects if multiple are listed). Automatically ignores decorative DLC lockers.
- **`[UseContainerTypeAssignment:true]`**: **Master Gate** for selective assignment.
- **`[ContainerTypeAssignBlockName:<TerminalName>]`** + **`[ContainerTypeAssignSubtypeId:<ContainerTypeId>]`**: Paired lists mapping block names to specific loot tables.
- **`[ContainerTypeAssignmentReference:BlockName|ContainerTypeId,BlockName2|ContainerTypeId2]`**: Dictionary syntax alternative (`TagParse.TagStringDictionaryCheck`: comma-separated `key|value` pairs). **[HARD]** Every entry needs a `|` (a bare name throws `IndexOutOfRangeException`), and the duplicate check tests the *value* instead of the key, so listing the same block name twice throws on `Dictionary.Add`.
- **`[ClearExistingContainerTypes:true]`**: Flushes pre-existing container types before applying new ones.

> [!CAUTION]
> **[HARD] Silent Failure on List Count Mismatch**: In `ManipulationProfile.cs:1566`, MES checks `this.ContainerTypeAssignBlockName.Count == this.ContainerTypeAssignSubtypeId.Count`. If the counts differ, MES **silently drops all assignments** without error or warning.

### C. Non-Cargo Block Support (`MesContainerTypeKey`)
> [!NOTE]
> **Vanilla Limitation Solved**: In vanilla SE, only `IMyCargoContainer` blocks support `ContainerType`. Cockpits, lockers, cryo pods, and assemblers ignore it.
> **MES Engine Solution**: MES uses internal mod storage (`StorageTools.MesContainerTypeKey`) to assign container types to *any* block with an inventory. During spawn (`InventoryHelper.ApplyContainerTypes()`), MES generates content for all non-cargo blocks carrying this storage key.

### D. MES Loot Profiles (`[MES Loot]`)
```xml
<EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
  <Id>
    <TypeId>Inventory</TypeId>
    <SubtypeId>ModPrefix-Loot-WreckSupplies</SubtypeId>
  </Id>
  <Description>
    [MES Loot]
    [ContainerTypes:PersonalContainerSmall]
    [ContainerBlockTypes:MyObjectBuilder_CargoContainer/SmallBlockSmallContainer]
    [MinBlocks:1]
    [MaxBlocks:3]
    [AppendNameToBlock:true]
    [AppendedName: [Loot]]
  </Description>
</EntityComponent>
```

- `[ContainerTypes:<SubtypeId>]`: Assigns loot tables to matching container blocks.
- `[MinBlocks:<int>]` / `[MaxBlocks:<int>]`: Limits the number of containers receiving loot.
- `[AppendNameToBlock:true]` + `[AppendedName:<string>]`: Appends a suffix to the block custom name for HUD/terminal visibility.

> [!WARNING]
> **[KNOWN BUG] Terminal Name Suffix Failure**: In current MES builds, `[AppendNameToBlock:true]` often fails to update the block's custom name in the terminal. The loot is correctly inserted into the inventory, but the visual name suffix (e.g. ` [Loot]`) is not always applied to the block. This is a known engine/MES bug to be aware of when testing.

### E. Runtime Dynamic Loot Swapping (`[RivalAI Action]`)
RivalAI can dynamically swap container loot tables via triggers during combat or encounter progression:

```xml
<EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
  <Id>
    <TypeId>Inventory</TypeId>
    <SubtypeId>ModPrefix-Action-UnlockVaultLoot</SubtypeId>
  </Id>
  <Description>
    [MES AI Action]
    [ApplyContainerTypeToInventoryBlock:true]
    [ContainerTypeBlockNames:Vault-Safe]
    [ContainerTypeSubtypeIds:HighTierTechLoot]
  </Description>
</EntityComponent>
```

- **`[ApplyContainerTypeToInventoryBlock:true]`**: **Master Gate** for runtime container type changes.
- **`[ContainerTypeBlockNames:<TerminalName>]`** + **`[ContainerTypeSubtypeIds:<ContainerTypeId>]`**: Paired lists targeting inventory blocks when triggers execute.

