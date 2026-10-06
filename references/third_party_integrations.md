# Third-Party Mod & Framework Integrations

Engineering guidelines for integrating Modular Encounters Systems (MES) with major third-party frameworks: CoreSystems (WeaponCore), Defense Shields, AiEnabled, Water Mod, and Torch server plugins.

---

## 1. CoreSystems / WeaponCore (WC) Integration

MES contains built-in hooks for WeaponCore grids, but deep architectural mismatches require strict engineering workarounds:

### A. The 800m Turret Range Clamp
- **[HARD] Default Clamp**: On grid spawn and weapon randomization, MES executes `SetAutomatedWeaponRanges(useMax: false)` (`GridEntity.cs:1736`), clamping all automated weapon ranges to **800m**.
- **The Fix**: Any combat encounter with long-range or capital weapons must execute `[SetWeaponsToMaxRange:true]` in an early trigger action (e.g. on spawn, on player proximity, or on damage) to allow WC turrets to engage past 800m.

### B. The Dynamic Replacement Range Desync (The MES vs. WC Conflict)
- **[HARD] The Bug**: When weapons are dynamically swapped via `[RandomizeWeapons:true]` or a block replacer profile (`[BlockReplacerProfileNames:]`), `SetWeaponsToMaxRange:true` frequently **fails to unclamp the weapons**.
  - In `WeaponRandomizer.cs:1321`, MES queries `APIs.WeaponCore.GetMaxWeaponRange(termBlock, 0)`.
  - Because WeaponCore registers newly spawned blocks asynchronously, the API call often returns `0` or default range before WC finishes registration.
  - Furthermore, `GetMaxWeaponRange` in WC returns the current slider range (`MaxTargetDistance`) rather than the true maximum range, so clamping to 800m causes WC to report 800m as the maximum.
  - MES permanently caches this stale value in `DefaultRangeWC` (`WeaponRandomizer.cs:1322`), locking the replaced weapon at 800m or 0m permanently.
  - Dynamically replaced blocks also lose any WeaponCore terminal/GUI settings saved in the original prefab blueprint.
- **[HARD] The Engine Fix**:
  - **Startup Pre-Caching**: In `AddonManager.WeaponCoreCallback()`, pre-populate `DefaultRangeWC` from `APIs.WeaponCore.WeaponDefinitions` at world startup to eliminate runtime spawn race conditions entirely.
  - **Definition Fallback**: In `WeaponRandomizer.cs`, compute max range directly from `APIs.WeaponCore.WeaponDefinitions` (`GetWeaponCoreDefinitionMaxRange`) without entity dependencies.
  - **Fail-Safe Unclamping**: Pass `float.MaxValue` when `useMax` is `true` if range is unresolvable, forcing WeaponCore's internal clamp to set the true maximum range and preventing 0m locking.
  - **Cache Guard**: Never cache `<= 0` in `DefaultRangeWC`.
- **Production Rule**: When designing high-stakes combat encounters on vanilla/unpatched MES builds, **do not dynamically replace primary WeaponCore weapons**. Bake the exact WeaponCore weapon blocks directly into the prefab blueprint with their ranges, targeting modes, and fire rates pre-configured.

### C. Getting MES to Fire WC Fixed Weapons (Prefab Setup & Proxying)
- **[HARD] Why MES-driven fixed guns never fire: the default shoot mode ignores MES.** MES calls `ToggleWeaponFire` (`CoreWeapon.cs:443`), which WeaponCore turns into `RequestShootSync(0, On, Signals.On)` (CoreSystems `ApiBackend.cs:1151`). WeaponCore only acts on that "On" trigger when the weapon's shoot mode is not `AiShoot` (or the signal is `Manual`): `onConfirmed = Trigger == On && (ShootMode != AiShoot || Signal == Manual)` (`SessionUpdate.cs:576`). `AiShoot` (terminal: "Auto (AI Controlled)") is the default (`ProtoWeapon.cs:616`), and a fixed gun (`TrackTargets:false`, `TurretAttached:false`) cannot fire itself in it, so the command is dropped. Setting the block to **Mouse Control** makes MES-driven fixed guns fire (confirmed in game); `KeyToggle`/`KeyFire` also pass the code check but are untested. MES and the WC API cannot set the mode, so it must be saved in the prefab (protobuf in the block's `ModStorageComponent`). `scripts/wc_shootmode.py` lists and sets it. `classify` sorts each weapon into TURRET (leave on Auto), FIXED-TRACKING (on Auto it fires itself only at projectiles, and only with `Smart` ammo, §G row D; MES fires it on Mouse Control), FIXED (never fires on Auto) or FLARE (§F). `audit --mods <weapon defs>` lints prefabs: it warns on every FIXED gun left on Auto and every FLARE taken off Auto. Use `--exclude` for prefabs MES never fires, e.g. static Wrecks. If the Timer Block proxy below was built because MES's own firing never worked, this may have been the reason. Details: `aircraft_behaviors_and_tuning.md` section 3B.
- **Prefab Pre-Configuration**: Fixed forward-firing weapons must have their WeaponCore settings properly configured before saving the blueprint:
  - **The shoot mode must NOT be "Auto (AI Controlled)"** (see the first bullet below). Set it to **Mouse Control** and save the prefab/blueprint.
  - Correct weapon ID/submunition slot verified.
- **[SOFT] Wide Aiming Tolerance**: Relaxing `[WeaponMaxAngleFromTarget]` from the default narrow value to **8°–12°** significantly helps MES fire fixed guns reliably. Gyro overshoot causes constant near-miss alignment failures at tight tolerances. This applies to **both WC and vanilla fixed weapons**. Confirmed on live server (GVK): wide tolerance is one of the effective workarounds even when Mouse Control mode is correctly set. See §1E for the full `[RivalAI Weapons]` template.
- **The Alignment Flicker Trap**:
  - In `CoreWeapon.cs:443`, MES calls `APIs.WeaponCore.ToggleWeaponFire(true)` when aligned to target and immediately calls `ToggleWeaponFire(false)` if the grid alignment deviates by even a fraction of a degree (`WeaponMaxAngleFromTarget`).
  - Due to gyro overshoot and rotational damping, alignment flickers every tick. For beam weapons, burst cannons, or charge-up railguns, this causes constant stuttering and aborted firing cycles where weapons never complete a shot.
- **[LEGACY] Timer Block Proxy** (no longer needed): Before the AiShoot root cause was identified, a common workaround was triggering a Timer Block that executed WC's own "Shoot Once" terminal action — bypassing the `ToggleWeaponFire` API entirely. This worked because WC honors its own terminal actions regardless of shoot mode. With Mouse Control now the correct fix, the proxy is obsolete for new builds. Existing prefabs that use it can be left as-is.


### D. The Target Lead Prediction Disaster
- **[HARD] MES ignores WeaponCore's `AimLeadingPrediction`.** MES leads targets itself (`UseProjectileLeadPrediction` / `UseCollisionLeadPrediction` autopilot tags, `AutoPilotSystem.cs:1275-1290`); the WC weapon-definition field only affects WC's own aiming (turrets), so changing it does nothing for a fixed gun MES is flying.
- **Why MES Misses 100% of Fixed Shots**:
  - In `AutoPilotSystem.cs:1304`, MES computes target lead using `VectorHelper.TrajectoryEstimation()`, which assumes a simple linear projectile speed, constant acceleration, and zero drag.
  - WeaponCore ammos feature complex ballistic physics: drag curves, acceleration profiles, gravity multipliers, multi-stage velocities, and submunitions that MES's solver cannot model.
  - SE gyroscope rotational inertia causes the NPC ship to constantly hunt and overshoot `_calculatedWeaponPredictionWaypoint`. Against an evasive or maneuvering player ship, fixed weapons spray wildly into empty space.

### E. The NPC Weapon Handicap Architecture
To bring NPC fixed-weapon accuracy on par with player grids, use these proven modding patterns:

1. **Smart / Guided Ammunition**:
   - Equip NPC-only weapons with WeaponCore smart ammunition (`Guidance: Smart` or `Guided`, tracking cones, proximity detonation / flak burst).
   - The NPC only needs to aim within the forward hemisphere; the ammunition closes the lead gap and tracks maneuvering player grids.

2. **Low-Arc Gimbaled Mounts (Disguised as Fixed)**:
   - Configure the weapon in WeaponCore with a small gimbal arc (e.g. 5°–15° traverse/elevation).
   - Lets **WeaponCore's native 60 FPS predictive solver** aim the barrel directly at the target, completely bypassing MES's clumsy hull-turning autopilot.

3. **High-Velocity / Near-Hitscan Projectiles**:
   - Drastically boosting muzzle velocity (e.g. 2,500–4,000 m/s or energy beams) collapses time-to-target (\(t = d / v\)), making lead calculation errors negligible.

4. **NPC-Only Weapon Protection (`<Public>false</Public>`)**:
   - Set `<Public>false</Public>` in the weapon's SBC definition to prevent players from grinding and salvaging these aim-assisted/homing weapons.
   - Pair with `[MES Weapon Mod Rules]` (`[AllowIfNonPublic:true]`) so MES does not skip them during spawning:
     ```xml
     <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
       <Id>
         <TypeId>Inventory</TypeId>
         <SubtypeId>ModPrefix-WeaponRules-NpcGuns</SubtypeId>
       </Id>
       <Description>
         [MES Weapon Mod Rules]
         [WeaponBlock:MyObjectBuilder_SmallMissileLauncher/NPC_GuidedRocketPod]
         [AllowIfNonPublic:true]
       </Description>
     </EntityComponent>
     ```

5. **`[RivalAI Weapons]` Profile Tuning**:
   - In `[RivalAI Weapons]`, relax `[WeaponMaxAngleFromTarget]` (e.g. from 2° to 8°–12°) so the NPC doesn't withhold fire forever while gyro-hunting:
     ```xml
     <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
       <Id>
         <TypeId>Inventory</TypeId>
         <SubtypeId>ModPrefix-Weapons-NpcCombat</SubtypeId>
       </Id>
       <Description>
         [RivalAI Weapons]
         [UseStaticGuns:true]
         [UseTurrets:true]
         [WeaponMaxAngleFromTarget:10]
         [WeaponMaxBaseDistanceTarget:3000]
       </Description>
     </EntityComponent>
     ```

### F. Flares (Anti-Smart Ammo) on NPCs
Checked against MES `13bcb1d` and WeaponCore workshop `3154371364` (`Data/Scripts/CoreSystems`).

**Bug status (both open as of 2026-10-04):** the MES flare-detection bug is tracked in https://github.com/GV-Server-Mods/GVK-Settings/issues/695, and the WeaponCore `LockedSmartOnly` bug in https://github.com/GV-Server-Mods/GVK-Settings/issues/696. Before relying on either bullet below, ask the user whether it has been fixed, or open the issue yourself if the user has given you permission to.

- **[HARD] MES flare logic only fires on a missile lock.** `CoreWeapon.cs:155-172` marks flare ammo `ReadyToFire` only when the weapon system has `[UseAntiSmartWeapons:true]` (default `false`) **and** `WeaponSystem.CheckForIncomingHomingProjectiles()` gets `true` from `APIs.WeaponCore.GetProjectilesLockedOn(RemoteControl)` (`WeaponSystem.cs:428`). Every other weapon goes through the normal readiness checks (§G).
- **[HARD] MES can't detect WeaponCore 2 flare ammo.** `CoreWeapon.cs:295` sets `_flareAmmo` only from the WC1 field `ammoDef.AreaEffect.AreaEffect == AreaEffectType.AntiSmart`. WC2 ammo defines anti-smart as `Ewar { Enable = true, Type = AntiSmartv2 }`. MES never reads `Ewar` for this, and its `EwarDef.EwarType` mirror in `API/CoreSystemsApiDefs.cs` stops at `Tractor`, without `AntiSmartv2`. So a WC2 flare launcher is handled as an ordinary fixed gun: `[UseAntiSmartWeapons]` does nothing for it, and §C's shoot-mode rules apply.
- **[HARD] WeaponCore bug: `LockedSmartOnly` is inverted.** It's documented as "only fire at smart projectiles locked on to parent grid". But `AcquireProjectile` (`Ai/AiTargeting.cs:684`) **skips** a smart projectile when its target block is on the weapon's own construct (`cube = lp.Info.Target.TargetObject`, then `IsSameConstructAs(...)` → `continue`). With it on, point defense and flares ignore exactly the missiles locked on their own grid. Leave it `false` until WeaponCore fixes it.
- **[SOFT] WC-native fix: let the flare launcher pick its own missiles (definitions code-checked; awaiting in-game confirmation).** Give the NPC flare block its own weapon definition. No turret subparts or Phantom are needed:
  - **AI:** fixed self-tracking, i.e. `TrackTargets = true`, `TurretAttached = false`, `TurretController = false`, azimuth/elevation parts `None`.
  - **Ammo: `Guidance = Smart`, with `Smarts { NoSteering = true, KeepAliveAfterTargetLoss = true, IgnoreAntiSmarts = true }`.** On Auto, WeaponCore fires a fixed weapon by itself only when its target is a projectile **and its own ammo is Smart or Drone**, within `AimingTolerance` (`AiShooting`, `SessionUpdate.cs:818-825`). A `Guidance = None` flare never launches by itself; GVK confirmed this in game. `NoSteering` keeps the Smart flare flying straight. Give NPCs their own copy of the flare ammo so player flares don't change.
  - **Targeting:** `Threats = { Projectiles }`, `IgnoreDumbProjectiles = true` (smart projectiles only), `LockedSmartOnly = false` (see the bug above), and a short `MaxTargetDistance` (about the flare field radius) so it only answers missiles close to its own grid.
  - **HardPoint:** `AimingTolerance = 180`, so it fires whatever direction the missile comes from. Tune `ShotsInBurst` / `DelayAfterBurst` so one missile doesn't empty the magazine.
  - **Prefab:** leave the block on **Auto (AI Controlled)** (`wc_shootmode.py audit` warns if a FLARE isn't). WeaponCore fires it, and on Auto it ignores MES fire commands (`SessionUpdate.cs:576`), so MES can't spam it.
- **[SOFT] Legacy-field workaround (untested).** WC2's `AmmoDef` still has the WC1 `AreaEffect` struct (`[ProtoMember(13)] AreaDamageDef AreaEffect`, with `AreaEffectType.AntiSmart`). Setting it on an NPC-only flare ammo next to the `Ewar` block should make MES set `_flareAmmo`. Whether WC2 itself reacts to the legacy field is unverified.

### G. NPC Weapon Setup Matrix (who pulls the trigger)
Code-checked against MES `13bcb1d` and WeaponCore workshop `3154371364`. Three facts decide every case: the weapon **class** (`wc_shootmode.py classify`), how MES reads the **ammo guidance**, and the **shoot mode** saved in the prefab.

| Ammo guidance | MES (`CoreWeapon.cs`) | WeaponCore on a MES "On" command (Mouse Control) |
|---|---|---|
| `None` (dumb) | Normal gun: fires when lined up within `[WeaponMaxAngleFromTarget]`, line of sight clear, in range (`:177`, `BaseWeapon.cs:292`) | Fires; no target needed (`RequiresTarget` false, `AmmoConstants.cs:450`) |
| `Smart` / `TravelTo` | **Homing:** fires once it has a target in range whose type is in the weapon's WC `Threats`. **No cone, no line-of-sight check** (`:85-150`, `:294`) | Fires only if the weapon holds a target (`RequiresTarget`), with **no aim check** (`SkipAimChecks` for Smart on fixed mounts, `AmmoConstants.cs:576`; shoot gate `SessionUpdate.cs:839-841`). Target acquisition uses the grid's AI focus first (`AiTargeting.cs:149`), and MES sets that focus to its target (`WeaponSystem.cs:620-640`) |
| `Detect*` | Normal gun | These are **mine** guidances (`IsMine`, `AmmoConstants.cs:436`), not "fly straight, then home" |
| WC1 `AreaEffect AntiSmart` / WC2 `Ewar AntiSmartv2` | Flare / not detected (§F) | See §F |

| # | Situation | Shoot mode | MES weapon profile | Notes |
|---|---|---|---|---|
| A | Turrets (incl. gimbals) | Auto | `[UseTurrets:true]` | `[SetWeaponsToMaxRange:true]` or ranges stay clamped to 800 m (§A) |
| B | Dumb fixed gun on an MES-flown craft | **Mouse Control** | `[UseStaticGuns:true]`, cone **8-12°** | MES does lead and aim (§C/§D). A 180° cone means "fire whenever in range" |
| C | Fixed gun with `Smart` ammo (real homing, or a two-stage aim-assist round) on an MES-flown craft | **Mouse Control** | `[UseStaticGuns:true]`; cap range with `[MaxStaticWeaponRange]` | Neither MES nor WeaponCore checks the angle, so it fires off-angle whenever both have a target. The WC `Threats` list filters what MES fires at: a `Grids`-only list never fires at players on foot. Aim-assist pattern: a `Smart` base round with `SteeringLimit = 0` (no steering), plus a timed fragment (`PointAtTarget`, `PointType = Direct`, `DirectAimCone`, `ParentDies = true`). The fragment spawns aimed at the target with lead prediction, but only if the target is inside the cone (`Projectile.cs:3390-3440`); otherwise the base round flies on straight. Use a tracer-only base round so the two don't look like separate shots |
| D | Fixed self-tracking gun | Mouse Control (Auto only for point defense) | either | Auto: WeaponCore fires it by itself **only at projectiles, and only with `Smart`/Drone ammo**, within its `AimingTolerance`; it never auto-fires at grids or characters, and ignores MES. `AiShooting` (`SessionUpdate.cs:818-825`) needs `TargetLock` for any other target, and that is only set for `TurretController` weapons and slaved turret parts (`:704-719`, `:953-957`, `:1011-1012`). Mouse Control: MES decides, per the ammo table |
| E | Fixed guns on a static grid (Wreck, base) | Auto | either | It can't turn to aim, and Auto never fires a fixed gun at grids or characters (row D), so all fixed guns stay silent. Mouse Control with a wide cone fires blind |
| F | Flares | Auto | `[UseAntiSmartWeapons]` not needed | §F |
| G | Any MES-flown prefab | | | `wc_shootmode.py audit --mods <weapon defs>` warns on FIXED guns left on Auto and FLAREs taken off it; exclude static prefabs |

- **[HARD] Give every NPC copy of a weapon its own `PartName`.** MES finds a block's WeaponCore definition by `HardPoint.PartName` and takes the **first** match across all loaded definitions, for ammo restock (`InventoryHelper.cs:407-412`) and weapon setup (`WeaponSystem.cs:191-196`). If an `_NPC` definition shares its name with the player one, MES restocks the player's ammo list and reads the player's settings. On GVK this filled NPC flare launchers mostly with firework magazines they can't fire, so they ran dry after one load.

---

## 2. Defense Shields Integration

MES interfaces with DarkStar's Defense Shields API:

- **Shield Modulation**: NPC grids can automatically modulate shield frequency to resist incoming kinetic or energy damage based on combat triggers.
- **Overheat & Downed Shield Triggers**:
  - Use `[Type:Damage]` triggers to monitor shield collapse and execute defensive actions (e.g. popping decoy pods, activating jump drives, or triggering smoke screens).
- **Shield Bypass & Hardening**:
  - Specific action profiles can force shield generators to overcharge or enter emergency lockdown when boarding threats are detected.

---

## 3. AiEnabled Integration (Hostile Bot Crews)

The AiEnabled framework allows NPC grids to spawn walking, intelligent crew bots and combat androids:

- **Profile**: `[MES Bot Spawn]`
- **Required Subsystems**:
  - Grids must contain navigable interior corridors.
  - Spawners can be tied to Cryo Chambers, Medical Rooms, or Cockpits.
- **Roles**:
  - `Defender`: Patrols interior rooms and attacks players attempting to grind or hack blocks.
  - `Crew`: Ambient non-combat personnel.
  - `Boarder`: Deploys toward nearby player grids if within close proximity.

---

## 4. Water Mod & Hydrodynamic AI

When operating on worlds running the Water Mod:

- **Behavior Subclass**: Set `[BehaviorName:Nautical]` in `[RivalAI Behavior]`.
- **Autopilot Profile**: Use `[RivalAI Autopilot]` configured with nautical buoyancy locks.
- **Spawn Conditions**: Use `[MES Spawn Conditions]` with `[MustSpawnUnderwater:true]` (or `[CanSpawnUnderwater:true]`), `[MinWaterCoverage:]`/`[MaxWaterCoverage:]`, and for installations `[InstallationSpawnsOnWaterSurface:true]`/`[InstallationSpawnsUnderwater:true]` with `[MinWaterDepth:]`/`[MaxWaterDepth:]` (`MaxWaterDepth` defaults to `-1` = no maximum since MES 2.74.05; on 2.74.03-2.74.04 it defaulted to `0` and had to be set; see `spawning_and_conditions.md` §3.B).
- **Anti-Sinking Logic**: Ensure buoyancy tanks or flotation blocks are prioritized in defense triggers.

---

## 5. Torch Plugins & Server Compatibility

On dedicated servers running Torch or Magnetar/Pulsar plugins:

- **Grid Defender**: Suppresses low-speed collision damage while preserving high-speed missile damage. Ensure NPC collision evasion waypoints don't trigger false positives.
- **Voxel Clang Mitigation**: Falling or disabled aircraft must be despawned cleanly (`[ForceDespawn:true]`) rather than allowed to crash and penetrate terrain meshes, which traps rigid bodies in continuous Havok collision solver loops and craters sim-speed to 0.2.

