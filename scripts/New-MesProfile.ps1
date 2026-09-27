<#
.SYNOPSIS
    Scaffolding generator for production-ready, defensively engineered MES and RivalAI profiles.
.DESCRIPTION
    Generates standard Space Engineers SBC XML files following all MES/RivalAI native engine rules:
    - No XML comments inside <Description> (uses [//Comment] instead)
    - Single SubtypeId per <Id> block
    - Correct master gates for MES Events ([ChangeCounters:true], [SpawnEncounter:true], etc.)
    - Correct tag names for RivalAI ([Spawner:] vs [SpawnData:])
    - Workarounds for known engine bugs (800m turret clamp, zero-stripping in counter targets)
    
    Supported Patterns:
    1. DefendedWreck: Derelict encounter with damage/proximity triggers, defense drone spawner, and cleanup.
    2. ConvoyLeaderEscort: Cargo ship leader with follower escorts and break-formation combat behavior.
    3. DynamicZoneLadder: Dynamic territory zone with MES Event counter-driven radius progression ladder.
    4. StoreGrid: Economy store grid setup (Prefab StoreItem, FactionTypes_Economy Builder snippet, MES Store profile).
    5. DynamicStateNpc: Dynamic Behavior Subclass & Autopilot Switching (CargoShip transit -> Fighter dogfight -> transit return).
    6. PlanetaryInstallation: Static defended outpost with interior defense spawner, turret range unclamp, and distress beacon.
    7. CombatDrone: High-performance combat drone with Fighter behavior, 6-DOF strafing, lead prediction, and collision evasion.
    8. ReinforcementNetwork: Caller grid broadcasting command code on damage + responder grid receiving command and navigating to caller.
    9. BossEncounter: Multi-phase boss with health/damage thresholds, escalation phases, custom chat taunts, and weapon unclamp.
.PARAMETER Pattern
    Pattern type: 'DefendedWreck', 'ConvoyLeaderEscort', 'DynamicZoneLadder', 'StoreGrid', 'DynamicStateNpc', 'PlanetaryInstallation', 'CombatDrone', 'ReinforcementNetwork', 'BossEncounter'.
.PARAMETER ModPrefix
    Mod prefix to prevent profile collisions (e.g. 'GVK', 'MES').
    Mod prefix to prevent profile collisions (e.g. 'MYMOD', 'MES').
.PARAMETER Name
    Name identifier for the encounter/grid (e.g. 'IronDrifter', 'KharakConvoy').
    Name identifier for the encounter/grid (e.g. 'ScrapWreck', 'CargoConvoy').
.PARAMETER Faction
    Faction tag (e.g. 'DERELICT', 'GAALSIEN', 'COALITION').
    Faction tag (e.g. 'SPRT', 'TRAD', 'CIV').
.PARAMETER OutFile
    Target .sbc file path. Defaults to .\<ModPrefix>_<Name>_<Pattern>.sbc.
#>
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet(
        "DefendedWreck",
        "ConvoyLeaderEscort",
        "DynamicZoneLadder",
        "StoreGrid",
        "DynamicStateNpc",
        "PlanetaryInstallation",
        "CombatDrone",
        "ReinforcementNetwork",
        "BossEncounter"
    )]
    [string]$Pattern,

    [Parameter(Mandatory=$true)]
    [string]$ModPrefix,

    [Parameter(Mandatory=$true)]
    [string]$Name,

    [string]$Faction = "DERELICT",
    [string]$OutFile = ""
)

if ([string]::IsNullOrWhiteSpace($OutFile)) {
    $OutFile = ".\${ModPrefix}_${Name}_${Pattern}.sbc"
}

$sb = [System.Text.StringBuilder]::new()

function Append-Header($title) {
    [void]$sb.AppendLine('<?xml version="1.0" encoding="utf-8"?>')
    [void]$sb.AppendLine('<Definitions xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">')
}

function Append-Footer() {
    [void]$sb.AppendLine('</Definitions>')
}

switch ($Pattern) {
    "DefendedWreck" {
        Append-Header "Defended Wreck Pattern"
        [void]$sb.AppendLine(@"
  <SpawnGroups>
    <SpawnGroup>
      <Id>
        <TypeId>SpawnGroupDefinition</TypeId>
        <SubtypeId>${ModPrefix}-SpawnGroup-${Name}</SubtypeId>
      </Id>
      <Description>
        [Modular Encounters SpawnGroup]
        [SpawnConditionsProfiles:${ModPrefix}-SpawnCondition-${Name}]
        [UseGridDereliction:true]
        [DerelictionProfiles:${ModPrefix}-Dereliction-${Name}]
      </Description>
      <IsPirate>true</IsPirate>
      <Frequency>1.0</Frequency>
      <Prefabs>
        <Prefab SubtypeId="${ModPrefix}-Prefab-${Name}">
          <Position><X>0.0</X><Y>0.0</Y><Z>0.0</Z></Position>
          <Speed>0.0</Speed>
          <Behaviour>${ModPrefix}-Behavior-${Name}</Behaviour>
        </Prefab>
      </Prefabs>
    </SpawnGroup>
  </SpawnGroups>

  <EntityComponents>
    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-SpawnCondition-${Name}</SubtypeId>
      </Id>
      <Description>
        [MES Spawn Conditions]
        [RivalAiAnySpawn:true]
        [CutVoxelsAtAirtightCells:true]
        [CutVoxelSize:2.5]
        [FactionOwner:${Faction}]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Dereliction-${Name}</SubtypeId>
      </Id>
      <Description>
        [MES Dereliction]
        [UseSeparatePercentages:true]
        [MinIntegrityPercentage:20]
        [MaxIntegrityPercentage:65]
        [MinBuildPercentage:10]
        [MaxBuildPercentage:45]
        [Blocks:MyObjectBuilder_CubeBlock/LargeBlockArmorBlock]
        [MatchOnlyTypeId:true]
        [Chance:40]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Behavior-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Behavior]
        [BehaviorName:Passive]
        [Triggers:${ModPrefix}-Trigger-Damage-${Name}]
        [Triggers:${ModPrefix}-Trigger-Proximity-${Name}]
        [Triggers:${ModPrefix}-Trigger-Cleanup-${Name}]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Trigger-Damage-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Trigger]
        [Type:Damage]
        [UseTrigger:true]
        [StartsReady:true]
        [Actions:${ModPrefix}-Action-Damage-${Name}]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Action-Damage-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Action]
        [SetWeaponsToMaxRange:true]
        [SpawnEncounter:true]
        [Spawner:${ModPrefix}-Spawner-DefenseDrone-${Name}]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Spawner-DefenseDrone-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Spawn]
        [UseSpawn:true]
        [SpawningType:CustomSpawn]
        [FirstSpawnTimeMs:0]
        [SpawnGroups:${ModPrefix}-SpawnGroup-DefenseDrone]
        [MinDistance:100]
        [MaxDistance:300]
        [MinAltitude:30]
        [MaxAltitude:60]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Trigger-Proximity-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Trigger]
        [Type:PlayerNear]
        [UseTrigger:true]
        [TargetDistance:1500]
        [Actions:${ModPrefix}-Action-Proximity-${Name}]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Action-Proximity-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Action]
        [UseChatBroadcast:true]
        [ChatData:${ModPrefix}-Chat-Proximity-${Name}]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Chat-Proximity-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Chat]
        [UseChat:true]
        [StartsReady:true]
        [Author:${Faction} Automated Beacon]
        [Color:Red]
        [BroadcastChatType:Chat]
        [ChatMessages:WARNING: Restricted airspace. Trespassers will be fired upon.]
        [BroadcastRandomly:true]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Trigger-Cleanup-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Trigger]
        [Type:Timer]
        [UseTrigger:true]
        [MinCooldownMs:3600000]
        [MaxCooldownMs:3600001]
        [Actions:${ModPrefix}-Action-Cleanup-${Name}]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Action-Cleanup-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Action]
        [ForceDespawn:true]
      </Description>
    </EntityComponent>
  </EntityComponents>
"@)
        Append-Footer
    }

    "ConvoyLeaderEscort" {
        Append-Header "Convoy Leader & Escort Pattern"
        [void]$sb.AppendLine(@"
  <SpawnGroups>
    <SpawnGroup>
      <Id>
        <TypeId>SpawnGroupDefinition</TypeId>
        <SubtypeId>${ModPrefix}-SpawnGroup-Leader-${Name}</SubtypeId>
      </Id>
      <Description>
        [Modular Encounters SpawnGroup]
        [SpawnConditionsProfiles:${ModPrefix}-SpawnCondition-${Name}]
      </Description>
      <IsPirate>true</IsPirate>
      <Frequency>1.0</Frequency>
      <Prefabs>
        <Prefab SubtypeId="${ModPrefix}-Prefab-Leader-${Name}">
          <Position><X>0.0</X><Y>0.0</Y><Z>0.0</Z></Position>
          <Speed>15.0</Speed>
          <Behaviour>${ModPrefix}-Behavior-Leader-${Name}</Behaviour>
        </Prefab>
        <Prefab SubtypeId="${ModPrefix}-Prefab-Escort-${Name}">
          <Position><X>100.0</X><Y>50.0</Y><Z>100.0</Z></Position>
          <Speed>15.0</Speed>
          <Behaviour>${ModPrefix}-Behavior-Escort-${Name}</Behaviour>
        </Prefab>
      </Prefabs>
    </SpawnGroup>
  </SpawnGroups>

  <EntityComponents>
    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-SpawnCondition-${Name}</SubtypeId>
      </Id>
      <Description>
        [MES Spawn Conditions]
        [RivalAiAnySpawn:true]
        [FactionOwner:${Faction}]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Behavior-Leader-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Behavior]
        [BehaviorName:CargoShip]
        [AutopilotData:${ModPrefix}-Autopilot-Leader-${Name}]
        [Triggers:${ModPrefix}-Trigger-LeaderDamage-${Name}]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Autopilot-Leader-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Autopilot]
        [IdealMinSpeed:20]
        [IdealMaxSpeed:35]
        [FlyLevelWithGravity:true]
        [WaypointTolerance:50]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Trigger-LeaderDamage-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Trigger]
        [Type:Damage]
        [UseTrigger:true]
        [Actions:${ModPrefix}-Action-LeaderDamage-${Name}]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Action-LeaderDamage-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Action]
        [SetWeaponsToMaxRange:true]
        [BroadcastCommandProfiles:true]
        [CommandProfileIds:${ModPrefix}-Command-LeaderAttacked-${Name}]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Command-LeaderAttacked-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Command]
        [CommandCode:${ModPrefix}_ConvoyUnderAttack]
        [SingleRecipient:false]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Behavior-Escort-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Behavior]
        [BehaviorName:Escort]
        [AutopilotData:${ModPrefix}-Autopilot-Escort-${Name}]
        [Triggers:${ModPrefix}-Trigger-EscortBreakFormation-${Name}]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Autopilot-Escort-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Autopilot]
        [IdealMinSpeed:25]
        [IdealMaxSpeed:50]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Trigger-EscortBreakFormation-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Trigger]
        [Type:CommandReceived]
        [CommandReceiveCode:${ModPrefix}_ConvoyUnderAttack]
        [UseTrigger:true]
        [Actions:${ModPrefix}-Action-EscortEngage-${Name}]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Action-EscortEngage-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Action]
        [ChangeBehaviorSubclass:true]
        [NewBehaviorSubclass:Fighter]
        [SetWeaponsToMaxRange:true]
      </Description>
    </EntityComponent>
  </EntityComponents>
"@)
        Append-Footer
    }

    "DynamicZoneLadder" {
        Append-Header "Dynamic Zone Ladder Pattern"
        [void]$sb.AppendLine(@"
  <EntityComponents>
    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Zone-${Name}</SubtypeId>
      </Id>
      <Description>
        [MES Zone]
        [Name:${ModPrefix}_Zone_${Name}]
        [PublicName:${ModPrefix} ${Name} Zone]
        [Active:true]
        [Persistent:true]
        [Coordinates:{X:0.0 Y:0.0 Z:0.0}]
        [Radius:20000]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Event-LadderUp-${Name}</SubtypeId>
      </Id>
      <Description>
        [MES Event]
        [UseEvent:true]
        [UniqueEvent:false]
        [MinCooldownMs:5000]
        [MaxCooldownMs:5001]
        [ConditionIds:${ModPrefix}-EventCondition-LadderUp-${Name}]
        [ActionIds:${ModPrefix}-EventAction-LadderUp-${Name}]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-EventCondition-LadderUp-${Name}</SubtypeId>
      </Id>
      <Description>
        [MES Event Condition]
        [CheckCustomCounters:true]
        [CustomCounters:${ModPrefix}_${Name}_Points]
        [CustomCountersTargets:10]
        [CounterCompareTypes:GreaterOrEqual]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-EventAction-LadderUp-${Name}</SubtypeId>
      </Id>
      <Description>
        [MES Event Action]
        [ChangeZoneByName:true]
        [ZoneNames:${ModPrefix} ${Name} Zone]
        [ZoneRadiusChangeTypes:Add]
        [ZoneRadiusChangeAmounts:5000]
        [ChangeCounters:true]
        [DecreaseCounters:${ModPrefix}_${Name}_Points]
        [DecreaseCountersAmount:10]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Event-LadderDown-${Name}</SubtypeId>
      </Id>
      <Description>
        [MES Event]
        [UseEvent:true]
        [UniqueEvent:false]
        [MinCooldownMs:5000]
        [MaxCooldownMs:5001]
        [ConditionIds:${ModPrefix}-EventCondition-LadderDown-${Name}]
        [ActionIds:${ModPrefix}-EventAction-LadderDown-${Name}]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-EventCondition-LadderDown-${Name}</SubtypeId>
      </Id>
      <Description>
        [MES Event Condition]
        [CheckCustomCounters:true]
        [CustomCounters:${ModPrefix}_${Name}_Points]
        [CustomCountersTargets:-1]
        [CounterCompareTypes:LessOrEqual]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-EventAction-LadderDown-${Name}</SubtypeId>
      </Id>
      <Description>
        [MES Event Action]
        [ChangeZoneByName:true]
        [ZoneNames:${ModPrefix} ${Name} Zone]
        [ZoneRadiusChangeTypes:Subtract]
        [ZoneRadiusChangeAmounts:5000]
        [ChangeCounters:true]
        [IncreaseCounters:${ModPrefix}_${Name}_Points]
        [IncreaseCountersAmount:10]
      </Description>
    </EntityComponent>
  </EntityComponents>
"@)
        Append-Footer
    }

    "StoreGrid" {
        Append-Header "Store Grid Pattern"
        [void]$sb.AppendLine(@"
  <!-- 1. Vanilla StoreItem Definition -->
  <StoreItems>
    <StoreItem>
      <Id>
        <TypeId>MyObjectBuilder_StoreItemDefinition</TypeId>
        <SubtypeId>${ModPrefix}-StoreItem-${Name}</SubtypeId>
      </Id>
      <ItemType>Prefab</ItemType>
      <ItemPrefabName>${ModPrefix}-Prefab-${Name}</ItemPrefabName>
      <PricePerUnit>5000000</PricePerUnit>
      <Amount>1</Amount>
    </StoreItem>
  </StoreItems>

  <!-- 2. MES Store Profile -->
  <EntityComponents>
    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-StoreProfile-${Name}</SubtypeId>
      </Id>
      <Description>
        [MES Store]
        [FileSource:${ModPrefix}-StoreItems-${Name}.xml]
        [MinOfferItems:1]
        [MaxOfferItems:1]
        [RequiredOffers:${Name}]
      </Description>
    </EntityComponent>
  </EntityComponents>

  <!-- 
    NOTE FOR FactionTypes_Economy.sbc:
    In Keen's engine, grid sales ONLY function under <FactionType> with <SubtypeId>Builder</SubtypeId>.
    Ensure the following is added to your FactionTypes_Economy.sbc:

    <FactionType>
      <Id>
        <TypeId>FactionTypeDefinition</TypeId>
        <SubtypeId>Builder</SubtypeId>
      </Id>
      <GridsForSale>
        <PrefabSubtypeId>${ModPrefix}-Prefab-${Name}</PrefabSubtypeId>
      </GridsForSale>
    </FactionType>
  -->
"@)
        Append-Footer
    }

    "DynamicStateNpc" {
        Append-Header "Dynamic Behavior Subclass & Autopilot Switching Pattern"
        [void]$sb.AppendLine(@"
  <SpawnGroups>
    <SpawnGroup>
      <Id>
        <TypeId>SpawnGroupDefinition</TypeId>
        <SubtypeId>${ModPrefix}-SpawnGroup-${Name}</SubtypeId>
      </Id>
      <Description>
        [Modular Encounters SpawnGroup]
        [SpawnConditionsProfiles:${ModPrefix}-SpawnCondition-${Name}]
      </Description>
      <IsPirate>true</IsPirate>
      <Frequency>1.0</Frequency>
      <Prefabs>
        <Prefab SubtypeId="${ModPrefix}-Prefab-${Name}">
          <Position><X>0.0</X><Y>0.0</Y><Z>0.0</Z></Position>
          <Speed>25.0</Speed>
          <Behaviour>${ModPrefix}-Behavior-${Name}</Behaviour>
        </Prefab>
      </Prefabs>
    </SpawnGroup>
  </SpawnGroups>

  <EntityComponents>
    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-SpawnCondition-${Name}</SubtypeId>
      </Id>
      <Description>
        [MES Spawn Conditions]
        [RivalAiAnySpawn:true]
        [FactionOwner:${Faction}]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Behavior-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Behavior]
        [BehaviorName:CargoShip]
        [AutopilotData:${ModPrefix}-Autopilot-Cruise-${Name}]
        [SecondaryAutopilotData:${ModPrefix}-Autopilot-Combat-${Name}]
        [TargetData:${ModPrefix}-Target-${Name}]
        [Triggers:${ModPrefix}-Trigger-EnterCombat-Damage-${Name}]
        [Triggers:${ModPrefix}-Trigger-EnterCombat-Target-${Name}]
        [Triggers:${ModPrefix}-Trigger-ExitCombat-${Name}]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Autopilot-Cruise-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Autopilot]
        [IdealMinSpeed:25]
        [IdealMaxSpeed:45]
        [FlyLevelWithGravity:true]
        [WaypointTolerance:50]
        [MinimumPlanetAltitude:100]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Autopilot-Combat-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Autopilot]
        [IdealMinSpeed:55]
        [IdealMaxSpeed:95]
        [FlyLevelWithGravity:false]
        [UseVelocityCollisionEvasion:true]
        [AllowStrafing:true]
        [StrafeMinDurationMs:3000]
        [StrafeMaxDurationMs:6000]
        [UseProjectileLeadPrediction:true]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Target-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Target]
        [UseCustomTargeting:true]
        [Target:Block]
        [MaxDistance:4000]
        [MatchAllFilters:Relation]
        [Relations:Enemy]
        [MatchAllFilters:Powered]
        [BlockTargets:Guns]
        [BlockTargets:Thrusters]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Trigger-EnterCombat-Damage-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Trigger]
        [Type:Damage]
        [UseTrigger:true]
        [StartsReady:true]
        [Tags:Cruising]
        [Actions:${ModPrefix}-Action-EnterCombat-${Name}]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Trigger-EnterCombat-Target-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Trigger]
        [Type:TargetNear]
        [TargetDistance:2000]
        [UseTrigger:true]
        [StartsReady:true]
        [Tags:Cruising]
        [Actions:${ModPrefix}-Action-EnterCombat-${Name}]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Action-EnterCombat-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Action]
        [ChangeBehaviorSubclass:true]
        [NewBehaviorSubclass:Fighter]
        [ChangeAutopilotProfile:true]
        [AutopilotProfile:Secondary]
        [SetWeaponsToMaxRange:true]
        [DisableTriggerTags:Cruising]
        [EnableTriggerTags:InCombat]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Trigger-ExitCombat-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Trigger]
        [Type:NoTarget]
        [UseTrigger:true]
        [StartsReady:false]
        [MinCooldownMs:15000]
        [MaxCooldownMs:15001]
        [Tags:InCombat]
        [Actions:${ModPrefix}-Action-ExitCombat-${Name}]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Action-ExitCombat-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Action]
        [ChangeBehaviorSubclass:true]
        [NewBehaviorSubclass:CargoShip]
        [ChangeAutopilotProfile:true]
        [AutopilotProfile:Primary]
        [DisableTriggerTags:InCombat]
        [EnableTriggerTags:Cruising]
      </Description>
    </EntityComponent>
  </EntityComponents>
"@)
        Append-Footer
    }

    "PlanetaryInstallation" {
        Append-Header "Planetary Installation Pattern"
        [void]$sb.AppendLine(@"
  <SpawnGroups>
    <SpawnGroup>
      <Id>
        <TypeId>SpawnGroupDefinition</TypeId>
        <SubtypeId>${ModPrefix}-SpawnGroup-${Name}</SubtypeId>
      </Id>
      <Description>
        [Modular Encounters SpawnGroup]
        [SpawnConditionsProfiles:${ModPrefix}-SpawnCondition-${Name}]
      </Description>
      <IsPirate>true</IsPirate>
      <Frequency>1.0</Frequency>
      <Prefabs>
        <Prefab SubtypeId="${ModPrefix}-Prefab-${Name}">
          <Position><X>0.0</X><Y>0.0</Y><Z>0.0</Z></Position>
          <Speed>0.0</Speed>
          <Behaviour>${ModPrefix}-Behavior-${Name}</Behaviour>
        </Prefab>
      </Prefabs>
    </SpawnGroup>
  </SpawnGroups>

  <EntityComponents>
    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-SpawnCondition-${Name}</SubtypeId>
      </Id>
      <Description>
        [MES Spawn Conditions]
        [RivalAiAnySpawn:true]
        [RivalAiAtmosphericSpawn:true]
        [FactionOwner:${Faction}]
        [CutVoxelsAtAirtightCells:true]
        [CutVoxelSize:2.5]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Behavior-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Behavior]
        [BehaviorName:Passive]
        [TargetData:${ModPrefix}-Target-${Name}]
        [Triggers:${ModPrefix}-Trigger-Damage-${Name}]
        [Triggers:${ModPrefix}-Trigger-Distress-${Name}]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Target-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Target]
        [UseCustomTargeting:true]
        [Target:Block]
        [MaxDistance:4000]
        [MatchAllFilters:Relation]
        [Relations:Enemy]
        [MatchAllFilters:Powered]
        [BlockTargets:Guns]
        [BlockTargets:Thrusters]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Trigger-Damage-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Trigger]
        [Type:Damage]
        [UseTrigger:true]
        [StartsReady:true]
        [Actions:${ModPrefix}-Action-Damage-${Name}]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Action-Damage-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Action]
        [SetWeaponsToMaxRange:true]
        [SpawnEncounter:true]
        [Spawner:${ModPrefix}-Spawner-Guards-${Name}]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Spawner-Guards-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Spawn]
        [UseSpawn:true]
        [SpawningType:CustomSpawn]
        [FirstSpawnTimeMs:0]
        [SpawnGroups:${ModPrefix}-SpawnGroup-Guards]
        [MinDistance:150]
        [MaxDistance:300]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Trigger-Distress-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Trigger]
        [Type:Damage]
        [Conditions:${ModPrefix}-Condition-Distress-${Name}]
        [UseTrigger:true]
        [StartsReady:true]
        [Actions:${ModPrefix}-Action-Distress-${Name}]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Condition-Distress-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Condition]
        [UseConditions:true]
        [CheckHealthPercentage:true]
        [MaxPercentageOfHealthRemaining:90]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Action-Distress-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Action]
        [BroadcastCommandProfiles:true]
        [CommandProfileIds:${ModPrefix}-Command-Distress-${Name}]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Command-Distress-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Command]
        [CommandCode:${ModPrefix}_BaseUnderAttack]
        [SingleRecipient:false]
      </Description>
    </EntityComponent>
  </EntityComponents>
"@)
        Append-Footer
    }

    "CombatDrone" {
        Append-Header "Combat Drone Pattern"
        [void]$sb.AppendLine(@"
  <SpawnGroups>
    <SpawnGroup>
      <Id>
        <TypeId>SpawnGroupDefinition</TypeId>
        <SubtypeId>${ModPrefix}-SpawnGroup-${Name}</SubtypeId>
      </Id>
      <Description>
        [Modular Encounters SpawnGroup]
        [SpawnConditionsProfiles:${ModPrefix}-SpawnCondition-${Name}]
      </Description>
      <IsPirate>true</IsPirate>
      <Frequency>1.0</Frequency>
      <Prefabs>
        <Prefab SubtypeId="${ModPrefix}-Prefab-${Name}">
          <Position><X>0.0</X><Y>0.0</Y><Z>0.0</Z></Position>
          <Speed>50.0</Speed>
          <Behaviour>${ModPrefix}-Behavior-${Name}</Behaviour>
        </Prefab>
      </Prefabs>
    </SpawnGroup>
  </SpawnGroups>

  <EntityComponents>
    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-SpawnCondition-${Name}</SubtypeId>
      </Id>
      <Description>
        [MES Spawn Conditions]
        [RivalAiAnySpawn:true]
        [FactionOwner:${Faction}]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Behavior-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Behavior]
        [BehaviorName:Fighter]
        [AutopilotData:${ModPrefix}-Autopilot-${Name}]
        [TargetData:${ModPrefix}-Target-${Name}]
        [Triggers:${ModPrefix}-Trigger-CombatInit-${Name}]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Autopilot-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Autopilot]
        [IdealMinSpeed:55]
        [IdealMaxSpeed:95]
        [FlyLevelWithGravity:false]
        [UseVelocityCollisionEvasion:true]
        [AllowStrafing:true]
        [StrafeMinDurationMs:2000]
        [StrafeMaxDurationMs:5000]
        [UseProjectileLeadPrediction:true]
        [BarrelRollMinDurationMs:2000]
        [BarrelRollMaxDurationMs:4000]
        [CollisionEvasionWaypointCalculatedAwayFromEntity:true]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Target-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Target]
        [UseCustomTargeting:true]
        [Target:Block]
        [MaxDistance:4000]
        [MatchAllFilters:Relation]
        [Relations:Enemy]
        [MatchAllFilters:Powered]
        [BlockTargets:Guns]
        [BlockTargets:Thrusters]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Trigger-CombatInit-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Trigger]
        [Type:TargetNear]
        [TargetDistance:3000]
        [UseTrigger:true]
        [StartsReady:true]
        [Actions:${ModPrefix}-Action-CombatInit-${Name}]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Action-CombatInit-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Action]
        [SetWeaponsToMaxRange:true]
      </Description>
    </EntityComponent>
  </EntityComponents>
"@)
        Append-Footer
    }

    "ReinforcementNetwork" {
        Append-Header "Reinforcement Network Pattern"
        [void]$sb.AppendLine(@"
  <EntityComponents>
    <!-- Caller Grid Setup (Grid under attack) -->
    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Trigger-SendDistress-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Trigger]
        [Type:Damage]
        [UseTrigger:true]
        [StartsReady:true]
        [Actions:${ModPrefix}-Action-SendDistress-${Name}]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Action-SendDistress-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Action]
        [BroadcastCommandProfiles:true]
        [CommandProfileIds:${ModPrefix}-Command-Distress-${Name}]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Command-Distress-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Command]
        [CommandCode:${ModPrefix}_DistressSignal]
        [SingleRecipient:false]
      </Description>
    </EntityComponent>

    <!-- Responder Grid Setup (Patrol or garrison responding to call) -->
    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Trigger-ReceiveDistress-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Trigger]
        [Type:CommandReceived]
        [CommandReceiveCode:${ModPrefix}_DistressSignal]
        [UseTrigger:true]
        [Actions:${ModPrefix}-Action-RespondDistress-${Name}]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Action-RespondDistress-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Action]
        [ChangeBehaviorSubclass:true]
        [NewBehaviorSubclass:Fighter]
        [SetWeaponsToMaxRange:true]
      </Description>
    </EntityComponent>
  </EntityComponents>
"@)
        Append-Footer
    }

    "BossEncounter" {
        Append-Header "Boss Encounter Pattern"
        [void]$sb.AppendLine(@"
  <SpawnGroups>
    <SpawnGroup>
      <Id>
        <TypeId>SpawnGroupDefinition</TypeId>
        <SubtypeId>${ModPrefix}-SpawnGroup-${Name}</SubtypeId>
      </Id>
      <Description>
        [Modular Encounters SpawnGroup]
        [SpawnConditionsProfiles:${ModPrefix}-SpawnCondition-${Name}]
      </Description>
      <IsPirate>true</IsPirate>
      <Frequency>1.0</Frequency>
      <Prefabs>
        <Prefab SubtypeId="${ModPrefix}-Prefab-${Name}">
          <Position><X>0.0</X><Y>0.0</Y><Z>0.0</Z></Position>
          <Speed>10.0</Speed>
          <Behaviour>${ModPrefix}-Behavior-${Name}</Behaviour>
        </Prefab>
      </Prefabs>
    </SpawnGroup>
  </SpawnGroups>

  <EntityComponents>
    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-SpawnCondition-${Name}</SubtypeId>
      </Id>
      <Description>
        [MES Spawn Conditions]
        [RivalAiAnySpawn:true]
        [FactionOwner:${Faction}]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Behavior-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Behavior]
        [BehaviorName:Cruiser]
        [AutopilotData:${ModPrefix}-Autopilot-Cruiser-${Name}]
        [TargetData:${ModPrefix}-Target-${Name}]
        [Triggers:${ModPrefix}-Trigger-Phase1-Damage-${Name}]
        [Triggers:${ModPrefix}-Trigger-Phase2-HeavyDamage-${Name}]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Autopilot-Cruiser-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Autopilot]
        [IdealMinSpeed:15]
        [IdealMaxSpeed:30]
        [WaypointTolerance:75]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Target-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Target]
        [UseCustomTargeting:true]
        [Target:Block]
        [MaxDistance:5000]
        [MatchAllFilters:Relation]
        [Relations:Enemy]
        [MatchAllFilters:Powered]
        [BlockTargets:Guns]
        [BlockTargets:Power]
      </Description>
    </EntityComponent>

    <!-- Phase 1: Initial Damage -> Unclamp Weapons & Taunt -->
    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Trigger-Phase1-Damage-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Trigger]
        [Type:Damage]
        [UseTrigger:true]
        [StartsReady:true]
        [MaxActions:1]
        [Actions:${ModPrefix}-Action-Phase1-${Name}]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Action-Phase1-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Action]
        [SetWeaponsToMaxRange:true]
        [UseChatBroadcast:true]
        [ChatData:${ModPrefix}-Chat-Phase1-${Name}]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Chat-Phase1-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Chat]
        [UseChat:true]
        [StartsReady:true]
        [Author:${Faction} Command]
        [Color:Red]
        [BroadcastChatType:Chat]
        [ChatMessages:Hostile target confirmed. All batteries, open fire!]
        [BroadcastRandomly:true]
      </Description>
    </EntityComponent>

    <!-- Phase 2: Heavy Damage -> Spawn Escort Wave -->
    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Trigger-Phase2-HeavyDamage-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Trigger]
        [Type:Damage]
        [Conditions:${ModPrefix}-Condition-Phase2-${Name}]
        [UseTrigger:true]
        [StartsReady:true]
        [MaxActions:1]
        [Actions:${ModPrefix}-Action-Phase2-${Name}]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Condition-Phase2-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Condition]
        [UseConditions:true]
        [CheckHealthPercentage:true]
        [MaxPercentageOfHealthRemaining:50]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Action-Phase2-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Action]
        [SpawnEncounter:true]
        [Spawner:${ModPrefix}-Spawner-EscortWave-${Name}]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Spawner-EscortWave-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Spawn]
        [UseSpawn:true]
        [SpawningType:CustomSpawn]
        [FirstSpawnTimeMs:0]
        [SpawnGroups:${ModPrefix}-SpawnGroup-EscortWave]
        [MinDistance:200]
        [MaxDistance:400]
      </Description>
    </EntityComponent>
  </EntityComponents>
"@)
        Append-Footer
    }
}

[System.IO.File]::WriteAllText($OutFile, $sb.ToString(), [System.Text.Encoding]::UTF8)
Write-Host "Generated $Pattern profile at: $OutFile" -ForegroundColor Green
