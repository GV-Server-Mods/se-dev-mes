# Tag Recipes for Common MES Features

Known-good groups of tags for the features encounter designers build most. Each recipe lists every profile involved and the tags that must go together; the silent failure each pairing prevents is under the block. Build new profiles from these instead of copying another mod's.

Checked against MES master `5899d09`. `scripts/test_tag_recipes.py` pulls every block out of this file and runs the audits on it; run it after editing a recipe.

**How to read a block**: `== Name` starts a profile and is its SubtypeId; the next line is its header. Wrap each profile as shown in [Wrappers](#wrappers). Names use `MyMod-`; rename them all consistently. Tags not shown keep their MES defaults: look them up with `query_mes_tags.py --profile <type>` rather than writing defaults out.

---

## Wrappers

A profile is an `EntityComponent`; only the Description changes between types. A spawn group is a `SpawnGroup`. Lines starting with `<` in a recipe's spawn group block go inside its `<Prefabs>`.

```xml
<EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
  <Id>
    <TypeId>Inventory</TypeId>
    <SubtypeId>MyMod-Action-Example</SubtypeId>
  </Id>
  <Description>
    [RivalAI Action]
    [//Tags go here. Comments use [//...], never XML comments.]
  </Description>
</EntityComponent>

<SpawnGroup>
  <Id>
    <TypeId>SpawnGroupDefinition</TypeId>
    <SubtypeId>MyMod-SpawnGroup-Example</SubtypeId>
  </Id>
  <Description>
    [Modular Encounters SpawnGroup]
  </Description>
  <IsPirate>true</IsPirate>
  <Frequency>1.0</Frequency>
  <Prefabs>
    <Prefab SubtypeId="MyMod-Prefab-Example">
      <Position><X>0</X><Y>0</Y><Z>0</Z></Position>
      <Speed>0</Speed>
      <Behaviour>MyMod-Behavior-Example</Behaviour>
    </Prefab>
  </Prefabs>
</SpawnGroup>
```

A RivalAI profile only runs when something reaches it: behavior → `[Triggers:]` → `[Actions:]` → the profile. To use a trigger from a recipe, add `[Triggers:<name>]` to the behavior (one name per tag line).

---

## 1. Attach a RivalAI behavior

```mes
== MyMod-SpawnGroup-Raider
[Modular Encounters SpawnGroup]
[UseRivalAi:true]
[RivalAiReplaceRemoteControl:true]
[SpawnConditionsProfiles:MyMod-SpawnConditions-Raider]
<Prefab SubtypeId="MyMod-Prefab-Raider">
  <Position><X>0</X><Y>0</Y><Z>0</Z></Position>
  <Behaviour>MyMod-Behavior-Raider</Behaviour>
</Prefab>

== MyMod-SpawnConditions-Raider
[MES Spawn Conditions]
[SpaceCargoShip:true]
[FactionOwner:SPRT]

== MyMod-Behavior-Raider
[RivalAI Behavior]
[BehaviorName:Fighter]
```

- `[UseRivalAi:true]` + `[RivalAiReplaceRemoteControl:true]` **in the same manipulation profile** (here the spawn group's own Description). With only the first, no remote receives the behavior and MES hands the name to Keen's drone AI. `[ManipulationProfiles:MES-Manipulation-RivalAi]` sets both. → [manipulation_and_dereliction.md](manipulation_and_dereliction.md) §1
- The prefab needs a Remote Control; the one marked Main gets the behavior, else the first found. `[ApplyBehaviorToNamedBlock:]` picks one by name.
- A vanilla remote with a Keen drone behavior name in `<Behaviour>` and neither tag is also valid. `audit_mes_references.ps1` warns on mixes of the two.

## 2. Chat line with sound

```mes
== MyMod-Trigger-Contact
[RivalAI Trigger]
[UseTrigger:true]
[Type:AcquiredTarget]
[MaxActions:-1]
[MinCooldownMs:30000]
[MaxCooldownMs:45000]
[Actions:MyMod-Action-ContactChat]

== MyMod-Action-ContactChat
[RivalAI Action]
[UseChatBroadcast:true]
[ChatData:MyMod-Chat-Contact]

== MyMod-Chat-Contact
[RivalAI Chat]
[UseChat:true]
[BroadcastRandomly:true]
[IgnoreAntennaRequirement:true]
[IgnoredAntennaRangeOverride:3000]
[ChatMessages:Contact. Moving to intercept.]
[ChatAudio:ArcHudGPSNotification1]
[BroadcastChatType:Chat]
[ChatMessages:Target acquired.]
[ChatAudio:ArcHudGPSNotification1]
[BroadcastChatType:Chat]
```

- `[UseChatBroadcast:true]` + `[ChatData:]`: the gate is off by default.
- One `[ChatAudio:]` and one `[BroadcastChatType:]` per `[ChatMessages:]`. Too few types sends nothing; too few sounds plays none. Common sounds: [dialogue_and_chat.md](dialogue_and_chat.md) §7.
- `[IgnoredAntennaRangeOverride:]` is the radius with `[IgnoreAntennaRequirement:true]`; `9999999` reaches the whole server. → §5 there
- An `AcquiredTarget` edge during the cooldown is dropped, which is what limits the chatter here. → §6 there

## 3. Dialogue bank cue

```mes
== MyMod-Behavior-Talker
[RivalAI Behavior]
[BehaviorName:Fighter]
[DialogueBanks:MyMod-Bank-Raider]
[Triggers:MyMod-Trigger-Attacked]

== MyMod-Trigger-Attacked
[RivalAI Trigger]
[UseTrigger:true]
[Type:Damage]
[DamageTypes:Any]
[MaxActions:-1]
[MinCooldownMs:20000]
[MaxCooldownMs:30000]
[Actions:MyMod-Action-AttackedCue]

== MyMod-Action-AttackedCue
[RivalAI Action]
[PlayDialogueCue:true]
[DialogueCueId:Attacked]

== MyMod-Chat-BankRadio
[RivalAI Chat]
[UseChat:true]
[BroadcastChatType:Chat]
[IgnoreAntennaRequirement:true]
[IgnoredAntennaRangeOverride:3000]
```

```xml DialogueBanks/MyMod-Bank-Raider
<DialogueBank>
  <ChatProfileId>MyMod-Chat-BankRadio</ChatProfileId>
  <DialogueCue>
    <DialogueCueId>Attacked</DialogueCueId>
    <Entries>
      <Entry><Message>Taking fire!</Message><AudioId>ArcHudGPSNotification2</AudioId><Weights>1</Weights></Entry>
      <Entry><Message>We're hit!</Message><AudioId>ArcHudGPSNotification2</AudioId><Weights>1</Weights></Entry>
    </Entries>
  </DialogueCue>
</DialogueBank>
```

- The bank file sits in `Data/DialogueBanks/` and `[DialogueBanks:]` is its exact file name.
- The bank's chat profile needs `[UseChat:true]` and one `[BroadcastChatType:]`, and no `[MaxChats:]`/`[MinTime:]`/`[MaxTime:]`: every grid on the bank shares that one profile object. → [dialogue_and_chat.md](dialogue_and_chat.md) §2
- `[Type:Damage]` + `[DamageTypes:Any]`: without a damage type the trigger never fires.

## 4. Reinforcements spawned from a trigger

```mes
== MyMod-Trigger-CallReinforcements
[RivalAI Trigger]
[UseTrigger:true]
[Type:Damage]
[DamageTypes:Any]
[MaxActions:1]
[Actions:MyMod-Action-CallReinforcements]

== MyMod-Action-CallReinforcements
[RivalAI Action]
[SpawnEncounter:true]
[Spawner:MyMod-Spawner-Reinforcements]

== MyMod-Spawner-Reinforcements
[RivalAI Spawn]
[UseSpawn:true]
[SpawnGroups:MyMod-SpawnGroup-Reinforcement]
[MinDistance:800]
[MaxDistance:1200]
[MinAltitude:150]
[MaxAltitude:300]

== MyMod-SpawnGroup-Reinforcement
[Modular Encounters SpawnGroup]
[RivalAiAnySpawn:true]
[FactionOwner:SPRT]
[UseRivalAi:true]
[RivalAiReplaceRemoteControl:true]
<Prefab SubtypeId="MyMod-Prefab-Reinforcement">
  <Position><X>0</X><Y>0</Y><Z>0</Z></Position>
  <Behaviour>MyMod-Behavior-Raider</Behaviour>
</Prefab>
```

- `[SpawnEncounter:true]` + `[Spawner:]` in a RivalAI Action; an MES Event Action names the same profile with `[SpawnData:]` instead (recipe 5).
- `[UseSpawn:true]`, and always set the distances: they default to `0`-`1` m, which spawns the group on top of the caller.
- The spawn group needs a `[RivalAi...Spawn:true]` condition, or it is never eligible for a `[RivalAI Spawn]`. → [spawning_and_conditions.md](spawning_and_conditions.md) §3
- Inside a player's Known Player Location only the KPL faction's groups spawn. → [events_and_zones.md](events_and_zones.md) §4 rule 7
- The spawned grid's parent is the caller, which recipe 13 relies on.

## 5. Counter gate in an event

```mes
== MyMod-Event-RaidBootstrap
[MES Event]
[UseEvent:true]
[UniqueEvent:true]
[ActionIds:MyMod-EventAction-RaidReset]

== MyMod-Event-RaidWave
[MES Event]
[UseEvent:true]
[MinCooldownMs:60000]
[MaxCooldownMs:120000]
[ConditionIds:MyMod-EventCondition-RaidEmpty]
[ActionIds:MyMod-EventAction-RaidSpawn]
[ActionIds:MyMod-EventAction-RaidReset]

== MyMod-EventCondition-RaidEmpty
[MES Event Condition]
[CheckCustomCounters:true]
[CustomCounters:MyMod_RaidWave]
[CustomCountersTargets:1]
[CounterCompareTypes:Less]

== MyMod-EventAction-RaidSpawn
[MES Event Action]
[SpawnEncounter:true]
[SpawnData:MyMod-Spawner-Reinforcements]
[SpawnCoords:{X:12000 Y:-4000 Z:3500}]
[SpawnFactionTags:SPRT]

== MyMod-EventAction-RaidReset
[MES Event Action]
[ChangeCounters:true]
[SetCounters:MyMod_RaidWave]
[SetCountersAmount:3]
```

- `[CheckCustomCounters:true]` + names, targets and compare types of equal length. `[ChangeCounters:true]` + `[SetCounters:]`/`[SetCountersAmount:]`.
- A counter target of `0` is stripped (`[CustomCountersTargets:0]` becomes an empty list). "Is zero or less" is `Less` than `1`, as here. → [events_and_zones.md](events_and_zones.md) §3
- A counter nobody has written yet fails every comparison, so the `[UniqueEvent:true]` bootstrap sets it first. An event with no `[ConditionIds:]` always passes.
- Sandbox counter names are server-wide: prefix them with your mod.

## 6. React below a health threshold

```mes
== MyMod-Trigger-Crippled
[RivalAI Trigger]
[UseTrigger:true]
[Type:Damage]
[DamageTypes:Any]
[MaxActions:1]
[Conditions:MyMod-Condition-BelowHalf]
[Actions:MyMod-Action-Withdraw]

== MyMod-Condition-BelowHalf
[RivalAI Condition]
[CheckHealthPercentage:true]
[MaxPercentageOfHealthRemaining:50]

== MyMod-Action-Withdraw
[RivalAI Action]
[ChangeAutopilotProfile:true]
[AutopilotProfile:Secondary]
```

- `[Type:HealthPercentage]` fires while health is at or *above* its threshold. For "below", use a `Damage` trigger with this condition. → [profiles_and_tags.md](profiles_and_tags.md) §2B
- `[AutopilotProfile:Secondary]` switches to the profile in the behavior's `[SecondaryAutopilotData:]`; set that slot on the behavior.
- A condition profile needs no gate (`[UseConditions:]` defaults to true).

## 7. Load and switch to a different autopilot

```mes
== MyMod-Action-LandingApproach
[RivalAI Action]
[OverwriteAutopilotProfile:true]
[OverwriteAutopilotMode:Tertiary]
[OverwriteAutopilotId:MyMod-Autopilot-Landing]
[ChangeAutopilotProfile:true]
[AutopilotProfile:Tertiary]

== MyMod-Autopilot-Landing
[RivalAI Autopilot]
[IdealMaxSpeed:20]
```

- **[HARD code, not flown] Unreliable:** MES sets the slot's profile but not its ID, so the next autopilot update reloads the old profile. Prefer declaring the profile in a slot (`[TertiaryAutopilotData:]`) and switching with `[ChangeAutopilotProfile:true]`. → [behaviors_and_autopilot.md](behaviors_and_autopilot.md) §2
- The overwrite only stores the profile in the slot; the change switches to it. Both run in one action, overwrite first.
- An unknown `[OverwriteAutopilotId:]` is ignored without a log line.

## 8. Despawn handling

```mes
== MyMod-Trigger-Gone
[RivalAI Trigger]
[UseTrigger:true]
[Type:DespawnMES]
[DespawnTypeFromSpawner:Any]
[MaxActions:1]
[Actions:MyMod-Action-GoneChat]

== MyMod-Action-GoneChat
[RivalAI Action]
[UseChatBroadcast:true]
[ChatData:MyMod-Chat-Gone]

== MyMod-Chat-Gone
[RivalAI Chat]
[UseChat:true]
[IgnoreAntennaRequirement:true]
[IgnoredAntennaRangeOverride:5000]
[ChatMessages:The convoy has left the area.]
[ChatAudio:ArcHudGPSNotification2]
[BroadcastChatType:Chat]
```

- `[Type:DespawnMES]` + `[DespawnTypeFromSpawner:Any]`: without a type the trigger never fires in normal play. It covers cleanup, behavior despawns and path ends, so don't add a `[Type:Despawn]` trigger with the same actions. → [behaviors_and_autopilot.md](behaviors_and_autopilot.md) §9
- The grid closes right after these actions: a command sent with `[CommandDelayTicks:]` is lost.

## 9. Spawn only inside a zone

```mes
== MyMod-Zone-Alpha
[MES Zone]
[Name:MyMod_Zone_Alpha]
[PublicName:Contested Territory Alpha]
[Active:true]
[Persistent:true]
[Coordinates:{X:62495 Y:28019 Z:37195}]
[Radius:25000]

== MyMod-SpawnConditions-AlphaOnly
[MES Spawn Conditions]
[SpaceCargoShip:true]
[FactionOwner:SPRT]
[ZoneConditions:MyMod-ZoneConditions-Alpha]

== MyMod-ZoneConditions-Alpha
[MES Zone Conditions]
[ZoneName:Contested Territory Alpha]
```

- `[ZoneName:]` must equal the zone's `[PublicName:]`; MES never looks a zone up by `[Name:]`.
- The zone must be `[Active:true]` and `[Persistent:true]` for a named zone condition to match.
- Zones can only be required, never excluded. To keep NPCs out, despawn them from an `[Type:InsideActiveZone]` trigger. → [events_and_zones.md](events_and_zones.md) §4

## 10. Act only after a state holds for a while

```mes
== MyMod-Trigger-NoContact
[RivalAI Trigger]
[UseTrigger:true]
[Type:Timer]
[MinCooldownMs:20000]
[MaxCooldownMs:20001]
[ConditionCheckResetsTimer:true]
[MaxActions:-1]
[Conditions:MyMod-Condition-NoTarget]
[Actions:MyMod-Action-BackToPatrol]

== MyMod-Condition-NoTarget
[RivalAI Condition]
[NoTarget:true]

== MyMod-Action-BackToPatrol
[RivalAI Action]
[ChangeAutopilotProfile:true]
[AutopilotProfile:Primary]
```

- `[ConditionCheckResetsTimer:true]` restarts the timer whenever the condition fails, so the action runs only after about 20 s without a target in a row. → [dialogue_and_chat.md](dialogue_and_chat.md) §6
- Prefer this over `[Type:NoTarget]`, which also fires before the first lock.

## 11. Unclamp weapon range

```mes
== MyMod-Trigger-WeaponsRange
[RivalAI Trigger]
[UseTrigger:true]
[Type:Timer]
[StartsReady:true]
[MaxActions:1]
[Actions:MyMod-Action-WeaponsRange]

== MyMod-Action-WeaponsRange
[RivalAI Action]
[SetWeaponsToMaxRange:true]
```

- Turret ranges are clamped to 800 m on spawn; this restores them once, right after spawn.
- Grids whose weapons were swapped by the randomizer or a block replacer often stay clamped. → [third_party_integrations.md](third_party_integrations.md) §1A-B
- **[SOFT]** Not checked: whether the clamp returns after a server restart, which `[MaxActions:1]` would not cover.

## 12. Loot in named cargo blocks

```mes
== MyMod-Manipulation-Loot
[MES Manipulation]
[UseContainerTypeAssignment:true]
[ContainerTypeAssignBlockName:Cargo-Valuable]
[ContainerTypeAssignSubtypeId:CargoLargeMilitary2A]
[ContainerTypeAssignBlockName:Cargo-Ammo]
[ContainerTypeAssignSubtypeId:AmmoStockpile]
```

- `[UseContainerTypeAssignment:true]` + block names and container types paired 1:1 by position; unequal counts drop every assignment. → [manipulation_and_dereliction.md](manipulation_and_dereliction.md) §6
- Names are the cargo blocks' exact `CustomName` in the prefab.
- Attach with `[ManipulationProfiles:MyMod-Manipulation-Loot]` on the spawn group.

## 13. Parent tells its spawned children what to do

```mes
== MyMod-Action-OrderRegroup
[RivalAI Action]
[BroadcastCommandProfiles:true]
[CommandProfileIds:MyMod-Command-Regroup]

== MyMod-Command-Regroup
[RivalAI Command]
[CommandCode:MyMod-Regroup]
[MatchReceiverChild:true]
[SendWaypoint:true]

== MyMod-Trigger-HearRegroup
[RivalAI Trigger]
[UseTrigger:true]
[Type:CommandReceived]
[CommandReceiveCode:MyMod-Regroup]
[MaxActions:-1]
[Actions:MyMod-Action-Regroup]

== MyMod-Action-Regroup
[RivalAI Action]
[AddWaypointFromCommand:true]
```

- "Child" means a grid this one spawned with a `[RivalAI Spawn]` (recipe 4); spawn group and event spawns have no parent. `[MatchReceiverChild:]` needs MES 2.75.00 or later. → [behaviors_and_autopilot.md](behaviors_and_autopilot.md) §5B-B2
- `[CommandCode:]` on the command must equal `[CommandReceiveCode:]` on the listener's trigger, which goes on the child's behavior.
- Delivery is instant: don't send a request and enable its reply listener in the same action. → §5C there
