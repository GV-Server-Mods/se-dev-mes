# Aircraft Attack Runs, Triggers, Weapons & Tuning

Companion to `behaviors_and_autopilot.md` for anything that flies (propeller aircraft and hover fighters). That file already covers the subclass list, the
`FighterPlane` breakaway (section 6B), the thruster-direction requirements (6A) and the `LevelWithGravity` pitch lockout (section 3A and 6D). This file adds what
is not there yet: how the attack-run cycle is tuned, which triggers swap profiles, the gates and ammo rules for fixed guns, **why WeaponCore fixed guns never fire from MES**, and a tuning method.

**Verified against**: MES 2.74.00 and CoreSystems (WeaponCore) 3.0 source, plus in-game testing of forward-thrust propeller aircraft. Hover/omni-thrust statements are read from source and
were **not** flight-tested unless stated. **[HARD]** = read in source (file:line given) or seen in a real log/prefab. **[SOFT]** = inferred or measured in play.

---

## 1. The attack-run cycle (`Strike` / `FighterPlane`) **[HARD]**

States: `WaitingForTarget` -> `ApproachTarget` -> `EngageTarget` -> back to `ApproachTarget` after the breakaway. `FighterPlane` is `Strike` line for line except the breakaway offset keeps the
plane's velocity direction (`FighterPlane.cs:256`); both read their distances from the **autopilot profile** whenever one is attached (`Strike.cs:22-25`), so the behavior-level
`[StrikeBegin...]` / `[FighterPlaneBegin...]` tags do nothing in practice. `Fighter` is the reverse: `[FighterEngageDistancePlanet:]` wins when set above 0 (`Fighter.cs:20`).

1. **Approach.** The autopilot flies to an **offset waypoint** around the target: `OffsetPlanetMinDistFromTarget` / `OffsetPlanetMaxDistFromTarget` away and
   `OffsetPlanetMinTargetAltitude` / `MaxTargetAltitude` above **the target's own position**, not the terrain (`OffsetSpace*` in space). Recalculated every `OffsetRecalculationTime` s (default 30).
   Which side of the target the offset lands on is random unless `OffsetMaxAngleFromTarget` limits it; that tag has caveats (`behaviors_and_autopilot.md` section 3E).
   Terrain floor: if that point would sit less than `MinimumPlanetAltitude` above the surface, MES moves it to `max(offset altitude, the midpoint of MinimumPlanetAltitude and IdealPlanetAltitude)` above the surface (`MathTools.ValueBetween` returns the midpoint, not a random value)
   (`AutoPilotSystem.cs:1597-1617`, MES 5fd61d1; the offset matrix is the target entity's world matrix, `:1531`). So against ground targets the line-up height is set by those two altitudes, and against air targets by the offset.
2. **Run start.** The run begins when the plane is within `AttackRunDistancePlanet` of the **offset waypoint** (not of the target) **and** the target is farther than
   `AttackRunBreakawayDistance`. With `AttackRunOverrideWithDistanceAndTimer:true` it is also forced when the plane stays within `AttackRunOverrideDistance` of the offset waypoint for
   `AttackRunOverrideTimerTrigger` s (stops a plane circling the offset forever). `AttackRunDistancePlanet` should exceed the turn radius (`speed / rotation rate`) or the plane can orbit the offset without
   getting inside. **[SOFT]**
3. **Run.** The waypoint becomes the target. `AttackRunUseSafePlanetPathing` keeps the terrain climb active; `AttackRunUseCollisionEvasionPlanet` (default false) leaves collision evasion off because the target itself would count as the obstacle.
4. **Run end.** The run ends when the distance to the target is `<= AttackRunBreakawayDistance` (default 450) or on `BehaviorActionA`. Then the next offset is picked.
   **`[AttackRunMaxTimeTrigger:]` does nothing.** The engage code checks `Data.AttackRunMaxTimeTrigger > 0` (`Strike.cs:239`, `FighterPlane.cs:239`) but `AutoPilotProfile.cs` has no parser for the tag, so it is always -1 (off).
5. **Distances that must agree.**
   - Offset distance = turn-around space. A longer offset gives a longer straight approach to line up, and a shallower dive (`atan(offset altitude / offset distance)`), which matters for targets on the ground.
   - The plane has to stay inside the target's acquisition range: compare the offset distance (plus turn-around overshoot) with the targeting profile's `MaxDistance` / `NonBroadcastVisualRange` and any `TargetFar` trigger distance (section 2).
   - The breakaway distance must leave room to pull out. Pull-out radius is about `speed / rotation rate`; a dive at angle `a` loses about `R * (1 - cos a)` plus gyro spin-up. **[SOFT]**
   - The gun firing window is roughly `MaxStaticWeaponRange - AttackRunBreakawayDistance` (section 3).
   - **Line up before the guns reach.** **[SOFT]** (GVK playtest) Put the offset distance at least 800 m beyond the fixed guns' max target distance, so the plane is lined up and on a straight approach before the target is in range, and widen the target profile's `MaxDistance` / `MaxExistingTargetDistance` and any `TargetNear`/`TargetFar` distances to cover the offset plus the turn-around (about 1 km), or the target is dropped between passes.
   - **Keep the target-relative offset altitude small, about -100 to 100, on every aircraft profile.** **[SOFT]** (GVK playtest) A line-up point well above the target makes NPC aircraft
     that target each other keep climbing over one another, and the dogfight cascades upward until it ends up in space. To keep planes higher over the ground, raise
     `MinimumPlanetAltitude` / `IdealPlanetAltitude` instead (the terrain floor above), which leaves air-to-air line-ups level.
   - The offset has to be reachable before it expires: `OffsetRecalculationTime` must exceed the flight time to the offset (`offset distance / speed`, plus the turn after a breakaway), or the plane chases a new offset every cycle and never starts a run. **[SOFT]**

**Speed during a run ([HARD] change in MES 2.74.06 dev).** This only matters with `[SlowDownOnWaypointApproach:true]`; the default is `false`, and then `CalculateStoppingDistance` returns `-1` and nothing below applies. With it on, `CalculateDirectForwardThrust` (the straight forward-thrust path a `FighterPlane` uses; a grid in gravity with a level-with-gravity profile uses the separate hover path instead) cuts forward thrust once `CalculateStoppingDistance(...)` reaches the waypoint distance (`ThrustSystem.cs:210`).
- **Up to MES 2.74.05** it passed `Direction.Forward`, so the estimate summed the **forward** thrusters (`ThrusterProfile.GetEffectiveThrust`), the same ones driven for forward thrust. On an aircraft with only forward propellers that gave a non-zero estimate, thrust was cut inside it and the plane **coasted** (it never braked down to `IdealMinSpeed`, and in a dive gravity added speed). Flight tests on forward-propeller aircraft matched this.
- **From commit `941e8c2` (2.74.06 dev, jayph)** it passes `Direction.Backward`: braking is measured with the reverse thrusters, as `behaviors_and_autopilot.md` section 6A item 2 always described. With no reverse thrusters `accel <= 0` and the estimate is `0`, so thrust is no longer cut by the slow-down; the plane keeps its throttle through a run. Reverse thrusters present: no change.
- **Dive caveat [HARD code, not flown]**: `CalculateStoppingDistance` still adds a gravity term to the acceleration (`dot(gravity, travelDir)`, `ThrustSystem.cs:503`), and `MathTools.StoppingDistance` uses `Math.Abs` on it, so gravity speeding the plane up in a dive is treated as braking. A forward-only plane in a dive therefore gets a non-zero estimate and can still lose thrust inside it once its speed is at or above `IdealMinSpeed`. In level flight the term is `0`, and in a climb the acceleration is negative, so the estimate is `0` and thrust is held. Expect the largest difference from 2.74.05 in level and climbing approaches, and the smallest in steep gun dives.
- Over-speed braking (`Brake To Desired Speed`) already used the reverse thrusters, so a forward-only plane still cannot brake in either build.
- Check which case applies with `/MES.IGGB` (AutoPilot section, `Forward Thrust Mode`, which shows the `Current Dist / Stop Dist` line). `/MES.BehaviorDebug.Thrust` logs only thruster removal: the thrust-mode log lines are commented out in `ThrustSystem.cs`. Where you want thrust held through a run on any build, set `SlowDownOnWaypointApproach:false`.

**`MaxVelocityAngleForSpeedControl`: keep it between 5 and 90 ([HARD], `ThrustSystem.cs:232-256`).** In `CalculateDirectForwardThrust` it decides whether speed control runs at all:
- **Velocity more than this many degrees off the waypoint direction:** full forward thrust, ignoring `IdealMaxSpeed`, any speed override and braking.
- **Within it:** speed control. Above `MaxSpeed + MaxSpeedTolerance` that means `Brake To Desired Speed`, which fires the **reverse** thrusters and never checks the direction of travel (it compares `velocity.Length()`, an unsigned speed).
- **Too low (the default 5°)** and a moving waypoint (an escort slot, an offset recalculated mid-flight) is almost never within the angle, so the grid flies at full thrust past it, turns, and overshoots again. MES's escort speed matching (`Escort.cs` sets `MaxSpeedOverride`) and `MaxSpeedTolerance` do nothing in that state.
- **Above 90** and the brake also runs while the grid is moving **away** from its waypoint. A grid facing its waypoint but moving away faster than `MaxSpeed` then "brakes" by thrusting away, gains speed, and never recovers (field-observed with the angle above 90: an escort 8 km from its slot at 150 m/s, velocity angle 179.6, IGGB showing `Brake To Desired Speed`). With 90 or less, a grid moving away falls through to full forward thrust, which faces the waypoint and stops it.
- **Use 90** for aircraft and escorts on moving waypoints: speed control while closing, a full-thrust stop once moving away. **[SOFT]**: 90 is reasoned from the code, not yet flight-tested. Never set 1000 or any other value above 90, even to "disable" the full-thrust kick.
- **Reported upstream:** MeridiusIX/Modular-Encounters-Systems#392 proposes using the forward component of the velocity (`forwardVelocityAmt`), as `CalculateHoverThrust` already does; the hover path is not affected. **Revise this rule if #392 is fixed:** with a direction-aware brake, values above 90 become safe and the cap can go.

### Autopilot tags that do little or nothing for aircraft **[HARD]**
Checked against MES `37455cf` (upstream master).

| Tag | What the code does |
| :--- | :--- |
| `UseRotationBoostUp`, `RotationBoostUpAmount` | Parsed (`AutoPilotProfile.cs:690-699`) but never read. No effect. |
| `DesiredAngleToTarget` | No parser; always 0. |
| `MinAngleForLeveledDescent`, `MaxAngleForLeveledAscent` | Only in `CalculateHoverThrust` (`ThrustSystem.cs:355-372`); planes on direct forward thrust never use them. |
| `TryToLevelWithTarget` | Only for a static target below ground within 1200 m (`AutoPilotSystem.cs:1115`). |
| `BehaviorActionA` / `B` | Read by `Strike`/`FighterPlane`, but no action tag sets them from SBC. |
| `UseCollisionLeadPrediction` | Aims at a collision course (no projectile travel time) and is checked before `UseProjectileLeadPrediction`, so it replaces gun leading (`AutoPilotSystem.cs:1277`). For rams, not guns. |
| `ReverseOffsetDistAltAboveHeight` + `ReverseOffsetHeight` | When the target is more than `ReverseOffsetHeight` above the surface, the offset distance and altitude ranges swap (`AutoPilotSystem.cs:1495-1511`): the line-up point goes offset-distance **above** the target. That is the upward cascade in item 5 above; avoid it for air-to-air. |

Tags that do work and are easy to miss:
- **`[Unused:]` (default true) breaks off an attack run** when a velocity collision is predicted within `CollisionTimeTrigger` (5 s, set in `SetDefaultTags`) (`FighterPlane.cs:252, 329`; `Strike.cs` the same). At 130 m/s that is about 650 m, so a run near terrain or close to the target can end before `AttackRunBreakawayDistance`.
- **`UseForcedRotationDampening` + `ForcedRotationDampeningAmount` (default off, 0.15):** after each gyro update MES cuts the grid's existing spin by the amount, directly through `Physics.SetSpeeds` (`RotationSystem.cs:47-80`). Less overshoot and wobble, slower turns. **[SOFT]** not flight-tested.
- **`RotationSlowdownAngle` (default 70):** above this error the gyro runs at full rate; below it the rate is the error in radians (`RotationSystem.cs:118`). It changes big turns only; small-angle wobble is already in the proportional range.
- **`MaxPlanetPathCheckDistance` (default 1000 m):** how far ahead planetary pathing scans terrain (`AutoPilotSystem.cs:2068`). At 130 m/s that is under 8 s of warning. The approach always uses planetary pathing; the run only with `AttackRunUseSafePlanetPathing:true`.
- **In gravity, a predicted terrain hit does not trigger collision evasion.** Voxel evasion runs only out of gravity; in gravity the only voxel case is the "fall" evade while moving within 15° of straight up (`AutoPilotSystem.cs:1037-1058`). Planetary pathing is what keeps planes off the ground.

---

## 2. Switching subclasses and profiles with triggers **[HARD]**

A common layout: a `Patrol` grid swaps to a combat subclass when a target appears, and back again.

| Trigger `[Type:]` | Fires when | Notes |
| :--- | :--- | :--- |
| `TargetNear` | a target exists and is closer than `[TargetDistance:]`; **also fires with no target if `AllowTargetFarWithoutTarget` is true** (`TriggerChecks.cs:47`) | "Start combat". Never put `AllowTargetFarWithoutTarget` on it (see below). |
| `TargetFar` | a target exists and is **farther** than `[TargetDistance:]` (`TriggerChecks.cs:54`) | **Needs a live target**; it can never fire once the target is dead or lost. `[AllowTargetFarWithoutTarget:true]` does nothing here (bug below). |
| `LostTarget` | the targeting system flagged the target lost (`TriggerChecks.cs:135`) | **Unreliable for "back to patrol"**: one-shot flag, see below. |
| `BehaviorTriggerA` / `B` | raised by the subclass: Patrol arrive / leave waypoint; Fighter engage / disengage; Strike & FighterPlane breakaway (A) / run start (B) | Use to swap autopilot profiles between phases. |

- **`[AutopilotProfile:]` takes a slot, not a profile name.** In an action it is an `AutoPilotDataMode` enum: `Primary`, `Secondary`, `Tertiary` (`ActionReferenceProfile.cs:264`, `AutoPilotSystem.cs:25`).
  The profiles behind the slots are named on the behavior profile: `[AutopilotData:<Id>]`, `[SecondaryAutopilotData:<Id>]`, `[TertiaryAutopilotData:<Id>]` (`AutoPilotSystem.cs:401/421/441`).
- **Every profile swap re-activates the autopilot from the new profile's tags** (`ActionSystem.cs:1790` -> `SetAutoPilotDataMode`, `AutoPilotSystem.cs:2370-2376`), copying `FlyLevelWithGravity` **and** `LevelWithGravityWhenIdle` into the state.
  This is a second way the pitch lockout in section 6D of `behaviors_and_autopilot.md` gets switched on, in addition to the engage activation that passes no `CheckEnum` arguments (`FighterPlane.cs:192`): with `LevelWithGravityWhenIdle:true` the mode is on after every swap.
  Keep both tags `false` in every profile of a wing-lift aircraft.
- **[HARD] `[AllowTargetFarWithoutTarget:]` is read by the wrong check** (MES 37455cf, since 2.1.22). The wiki says it lets `TargetFar` fire with no target, but only `CheckTargetNear` reads it (`TriggerChecks.cs:47`); `CheckTargetFar` (`:54`) always requires `HasTarget()`. **Fails as**: the plane stays in its combat subclass forever after its target despawns; FighterPlane sits motionless in `WaitingForTarget`. **Reported upstream:** MeridiusIX/Modular-Encounters-Systems#393 (move the no-target clause to `CheckTargetFar`). **Revise this rule if #393 is fixed:** `TargetFar` + the tag would then work as the wiki describes, and `TargetNear` would stop firing without a target.
- **[HARD] `LostTarget` is a one-shot flag shared by every `LostTarget` trigger on the grid.** `CheckLostTarget` returns `Targeting.TargetLost` and clears it (`TriggerChecks.cs:135-139`), and the trigger pass clears it again at its end (`TriggerSystem.cs:513`). Triggers are checked in the order the behavior lists them (`[Triggers:]` and `[TriggerGroups:]` in tag order), so the first `LostTarget` trigger that is off cooldown takes the flag and any later one never sees it. A trigger on cooldown skips its check and leaves the flag. **Fails as**: a "lost contact" chatter trigger in an earlier trigger group swallows the loss, and the patrol-return trigger never fires (intermittent: only while the chatter is off cooldown). **Reported upstream:** MeridiusIX/Modular-Encounters-Systems#394 (drop the per-check clear, as the `BehaviorTrigger*` checks already do). **Revise this rule if #394 is fixed:** every `LostTarget` trigger would then see the event in the same pass.
- **Reliable "back to patrol"**: a `[Type:Timer]` trigger (a few seconds' cooldown) with a condition `[NoTarget:true]` that activates the switch-to-patrol trigger. It is a state check, so it can't miss an edge. While the grid is already patrolling, a disabled switch-to-patrol `Manual` trigger makes it a no-op (`ProcessManualTrigger` skips triggers with `UseTrigger:false`). Keep `TargetFar` for "target still alive but out of range".
- **Hysteresis**: make the "back to patrol" distance clearly larger than the "start combat" distance so a plane at the boundary does not flip.
- `[EnableTriggerNames:]` does **not** reset a trigger's cooldown or count; only `[ResetTriggerCooldownNames:]` / `ToggledProfileResetsCooldown` do (`TriggerSystem.cs`). A `StartsReady:true` trigger skips its first cooldown (`TriggerProfile.cs:397`).

---

## 3. Weapons on aircraft

### A. MES's gates for fixed (static) guns **[HARD]**
`[RivalAI Weapons]` (`WeaponSystemReference.cs`). A fixed gun fires only when **all** hold (`BaseWeapon.cs`, `StaticDistanceAndAngleCheck`):

- the target (or waypoint) is within `MaxStaticWeaponRange`,
- the angle between the gun's forward axis and the target is `<= WeaponMaxAngleFromTarget` degrees (**default 6**),
- the point the gun's line reaches at target range is within `WeaponMaxBaseDistanceTarget` meters of the target (**default 20 m**, `WeaponSystemReference.cs:55-56`; 20 m at 1000 m range is about 1.1 deg, so with the default this is the tighter gate at almost any range; raise it together with the angle),
- no terrain or friendly grid is in the way.

`UseAmmoReplenish` (default true) gives an empty NPC gun `AmmoReplenishClipAmount` (default 15) magazines, up to `MaxAmmoReplenishments` times (**default 10**; `WeaponSystemReference.cs:61-63`, `CoreWeapon.cs:243`).
Leaving `MaxAmmoReplenishments` out does **not** make it unlimited, and MES has no infinite-ammo option.

### B. WeaponCore fixed guns must not be in "Auto (AI Controlled)" **[HARD]**
The usual reason "MES aims at the target but the WeaponCore guns never fire".

- MES fires a WC fixed gun with `ToggleWeaponFire(block, true, false, id)` (`CoreWeapon.cs:443`), which becomes `RequestShootSync(0, On, Signals.On)` (CoreSystems `ApiBackend.cs:1151`).
- WeaponCore only honors an "On" trigger when the weapon's shoot mode is **not** `AiShoot` (or the signal is `Manual`): `onConfirmed = Trigger == On && (ShootMode != AiShoot || Signal == Manual)` (`SessionUpdate.cs:576`).
- `AiShoot` is the default (`ProtoWeapon.cs:616`), shown as "Auto (AI Controlled)". A fixed gun (`TrackTargets:false`, `TurretAttached:false`) cannot fire itself in that mode, so MES's command is dropped.
- Setting the block to **Mouse Control** fixes it (confirmed in game). `KeyToggle` / `KeyFire` also pass the code check but were not tested. **[SOFT]**
- MES has no code to set the mode and the WC API has no setter, so it has to be **saved in the prefab/blueprint**. WeaponCore stores it as protobuf in the block's `ModStorageComponent` (key `75bbb4f5-4fb9-4230-beef-bb79c9811501`).
  `scripts/wc_shootmode.py` lists and sets it in `.sbc` prefabs, and its `classify` command tells fixed guns from turrets (turrets track and fire themselves; leave them on Auto).
- MES ignores WeaponCore's `AimLeadingPrediction`; it leads targets itself with the autopilot tags `UseProjectileLeadPrediction` (default true) / `UseCollisionLeadPrediction` (`AutoPilotSystem.cs:1275-1290`).

---

## 4. Hover / omni-thrust fighters **[SOFT]** (source-read, not flight-tested)

- `Fighter` approaches with `RotateToWaypoint | ThrustForward | PlanetaryPathing | WaypointFromTarget`, then **engages with `RotateToWaypoint | Strafe | WaypointFromTarget` and no `ThrustForward`**: it strafes with lateral/up/down thrusters and needs `[AllowStrafing:true]` (`Fighter.cs`). It needs thrusters in all six directions (see 6A).
- For hover craft, `LevelWithGravity` is the intended mode rather than a bug: in gravity with `ThrustForward` it swaps `CalculateDirectForwardThrust` for `CalculateHoverThrust` (`ThrustSystem.cs:70`), which holds altitude against the waypoint
  (`AltitudeTolerance`, `MaxVerticalSpeed`, `HoverUpAngle`). The price is the pitch lockout: the nose stays level, so a leveled hover craft will not nose-dive at targets. Never combine it with `UseSurfaceHoverThrustMode`.
- If a hover fighter must aim its nose up or down at targets, run it without `LevelWithGravity` and give it enough vertical thrust to hold altitude on its own.

---

## 5. Tuning method (what worked)

1. **Change one thing at a time and test it.** A rewrite that changed six numbers at once made every plane crash and identified nothing. Keep numbered copies of the behavior files and install one at a time.
2. **Measure the airframe before choosing numbers.** `scripts/PB_TurnTest.cs` is a Programmable Block script: on the NPC variant in steady flight it drives the gyros at a set yaw or pitch rate and prints how far the flight **path** turned (not just the nose), speed and altitude change at 90 and 180 deg.
   Typical findings: wings add little yaw authority, high nose rates bleed speed, path radius grows with speed squared. **[SOFT]**
3. **Read what MES actually loaded**: `/MES.Info.GetGridBehavior` (`/MES.IGGB`) prints the live autopilot flags, including `LevelWithGravity`.
4. **Find silent no-ops**: run `scripts/audit_unknown_tags.py` over your behavior folder; MES never reads a tag its parser does not know (a typo, or a tag from another profile type).

## 6. Debugging aircraft (commands are in `diagnostics_and_troubleshooting.md`, section B)

- **Guns silent while the plane lines up**: `/MES.BehaviorDebug.Weapon.true`. Each gun logs `NoAmmo`, `StaticWeaponNotAligned` (the flying is the problem, see 3A) or `ReadyToFire` + "Start Fire" (MES is firing; if nothing comes out, check 3B).
- **Yaws at the target but never pitches**: `/MES.IGGB` and look for `LevelWithGravity`; see section 2 above and 6D.
- **Speed is wrong**: `/MES.IGGB` (AutoPilot section, `Forward Thrust Mode`) shows the thrust branch ("Brake To Desired Speed", "Drifting At Desired Speed", "Thrust Angle Not Matched").
- **A spawn never produces the aircraft**: `/MES.SpawnDebug.SpawnGroup.true` prints why each group was rejected (for example "Could Not Get Valid NPC Faction" when the group's `FactionOverride` does not exist in the world). Without it the log only says "Eligible SpawnGroup Count 0".
