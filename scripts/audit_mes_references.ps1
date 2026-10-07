<#
.SYNOPSIS
    Cross-reference validator for MES and RivalAI profiles in Space Engineers SBC files.
.DESCRIPTION
    Scans all .sbc files in the target directory to:
    1. Collect all defined SubtypeIds across:
       - Triggers, TriggerGroups, Actions, Conditions, Spawners, Chats, Behaviors
       - SpawnGroups
       - Prefabs
       - MES Events, Event Actions, Event Conditions
       - Zones
    2. Collect all referenced SubtypeIds across:
       - Behavior profiles: [Triggers], [TriggerGroups], [AutopilotData],
         [SecondaryAutopilotData], [TertiaryAutopilotData], [TargetData], [WeaponSystem]
       - Trigger profiles: [Conditions], [Actions], [ElseActions], [DisableNamedTriggerOnSuccess]
       - TriggerGroup profiles: [Triggers]
       - Action profiles: [Spawner], [SpawnData], [Chat], [ChatData], [CommandProfileIds],
         [ToggleEventIds], [Enable/Disable/ResetTriggerCooldownNames], [WaypointsToAdd],
         [NewBehavior], [ContractBlockProfiles], [InstanceEventGroupId]
       - Condition profiles: [RequiredSpawnConditions], [PlayerConditionIds]
       - Spawner profiles: [SpawnGroups]
       - SpawnGroup definitions: [SpawnConditionsProfiles], [SpawnConditionGroups],
         [ManipulationGroups], <Prefab SubtypeId="...">, <Behaviour> (warning only)
       - Spawn condition / zone profiles: [ZoneConditions], [RestrictedSpawnGroups],
         [AllowedSpawnGroups]
       - Event profiles & templates: [ConditionIds], [PersistantConditionIds], [ActionIds],
         [TemplateEventIds]
       - Contract/mission profiles: [MissionIds], [StoreProfileId], [PlayerConditionIds],
         [LeadPlayerConditionIds], [PersistantEventConditionIds], [EventConditionIds]
       - Zone names (separate namespace): [ZoneName]/[ZoneNames] must match a [MES Zone]
         [PublicName] - MES never looks a zone up by its [Name]
       - Loot/Manipulation profiles: [ContainerTypes], [ContainerTypeAssignSubtypeId],
         [AssignContainerTypesToAllCargo], [ContainerTypeSubtypeIds], [BlockReplacerProfileNames]
    3. Collect and cross-reference the separate string-Tag broadcast system, distinct from
       SubtypeId lookups: [Tags:] declared on [RivalAI Trigger]/[MES AI Trigger] profiles
       and on [MES Event] profiles (two independent, non-unique, many-to-many pools - by
       design many profiles legitimately share one tag so a single broadcast can act on all
       of them at once, so - unlike SubtypeIds - Tags are never flagged as "duplicate
       definitions"). Consumers: [ManuallyActivatedTriggerTags:], [EnableTriggerTags:],
       [DisableTriggerTags:], [ResetTriggerCooldownTags:] (match the Trigger-tag pool) and
       [ActivateEventTags:], [ToggleEventTags:], [ResetEventCooldownTags:],
       [IncreaseRunCountEventTags:] (match the Event-tag pool). A tag referenced that no
       profile anywhere declares is flagged - the broadcast would silently do nothing.
    4. Cross-reference definitions and references to flag:
       - Missing / Dangling references (referenced but never defined)
       - Case mismatches (e.g. 'GVK-Action-Foo' vs 'GVK-Action-foo')
       - Orphaned definitions (defined but never referenced anywhere) - only for profile
         types MES never activates on its own (not SpawnGroups, Events, Zones, prefabs)

    Known false-positive sources this script deliberately suppresses, and how:
    - References to profiles shipped inside MES's own Data folder (e.g.
      MES-Manipulation-RivalAi) are resolved against scripts/mes_core_definitions.json
      instead of being flagged as missing.
    - References containing a runtime token (e.g. '{Faction}-Convoy') are only treated as
      possibly-resolvable for the small set of reference types confirmed (against the MES
      C# source) to have ANY substitution mechanism at all: SpawnGroup, Store, ToggleEvent,
      ResetEvent. For those, the token is turned into a wildcard and checked against every
      known definition: at least one match -> [INFO] Dynamic Token Reference (real, just
      not statically pinpointable); zero matches -> [ERROR] Dead Token Pattern (dead
      regardless of substitution - a real bug). For every OTHER reference type (Action,
      Trigger, Condition, TriggerGroup, ManipulationProfiles, LootProfiles, ContainerType,
      etc.) a token is flagged immediately as [ERROR] Token in Static Reference, because
      MES has no substitution mechanism for those tags at all - a token there is always
      dead on arrival, not a false positive. See the Pass 2 comment block for full
      source-verified evidence per reference type.
    - Files matching '*ContainerTypes*.sbc' are parsed with a dedicated block-aware rule:
      only the <ContainerType>'s own <Id><TypeId>ContainerTypeDefinition</TypeId>
      <SubtypeId> is registered as a definition. The <Items><Item><Id><SubtypeId> entries
      nested inside are commodity items (ore/ingot/component ids like Uranium), not MES
      profile definitions, and legitimately repeat across dozens of container types - so
      they are not registered and do not trigger duplicate-definition noise. Loot
      references ([ContainerTypes:], [ContainerTypeAssignSubtypeId:],
      [AssignContainerTypesToAllCargo:]) ARE still validated against real container-type
      definitions, MES's own shipped container types, and vanilla SE's stock container
      types (scripts/vanilla_container_types.json) - so a typo'd or non-existent loot
      table is still caught.
    - In other files a <SubtypeId> is a definition only inside a definition's own <Id>
      element. Elsewhere it is a reference (a spawn group's <Factions><SubtypeId>, a gas
      or faction id in a block or session component) and is not registered.
    - Spawn group <Prefab SubtypeId> references also resolve against vanilla SE's stock
      prefabs (scripts/vanilla_prefabs.json), so a mod may point a spawn group at, or
      redefine, a base-game prefab such as P26_HaulerWreck.
    - XML comments (<!-- ... -->) are blanked out before scanning, so a commented-out
      copy of a profile is not reported as a duplicate definition and its references
      are not validated.
    - Prefab/ship-blueprint files (Prefabs/StorePrefabs folders, or any file containing
      a PrefabDefinition/ShipBlueprintDefinition Id) register only that top-level grid
      Id. Nested item, component, and assembler-blueprint <Id> entries inside the grid
      are not profile definitions and are skipped.
.PARAMETER Path
    Path to the mod's Data or Content directory. Defaults to current directory.
.PARAMETER IncludePrefabs
    Whether to scan prefabs for definitions. Defaults to true.
.PARAMETER WarnOrphans
    Whether to warn about unused/orphaned profiles. Defaults to false.
#>
param(
    [string]$Path = ".",
    [switch]$IncludePrefabs = $true,
    [switch]$SkipPrefabs = $false,
    [switch]$WarnOrphans = $false
)

Write-Host "Scanning SBC files in: $Path" -ForegroundColor Cyan

# 1. Collect all .sbc files
$sbcFiles = Get-ChildItem -Path $Path -Filter *.sbc -Recurse
if ($sbcFiles.Count -eq 0) {
    Write-Host "No .sbc files found in $Path" -ForegroundColor Red
    exit 1
}

# SubtypeIds shipped natively by MES itself (RivalAI/manipulation/loot/spawn-condition
# profiles that live inside MES's own Data folder, not in the mod being audited).
# Referencing one of these is not a missing reference. Regenerate this list when MES
# updates — see scripts/mes_core_definitions.json for the extraction command.
$mesCoreDefinitions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$mesCoreDefPath = Join-Path $PSScriptRoot "mes_core_definitions.json"
if (Test-Path $mesCoreDefPath) {
    try {
        $mesCoreData = Get-Content -Raw $mesCoreDefPath | ConvertFrom-Json
        foreach ($d in $mesCoreData.definitions) { [void]$mesCoreDefinitions.Add($d) }
    } catch {
        Write-Host "[WARN] Could not parse mes_core_definitions.json - MES core profiles will not be recognized: $_" -ForegroundColor Yellow
    }
}

# ContainerTypeDefinition SubtypeIds shipped by vanilla Space Engineers itself (e.g.
# PersonalContainerSmall). A [ContainerTypes:]/[ContainerTypeAssignSubtypeId:] reference
# to one of these is valid even though it's never defined in this mod or in MES.
$vanillaContainerTypes = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$vanillaContainerTypesPath = Join-Path $PSScriptRoot "vanilla_container_types.json"
if (Test-Path $vanillaContainerTypesPath) {
    try {
        $vanillaCtData = Get-Content -Raw $vanillaContainerTypesPath | ConvertFrom-Json
        foreach ($d in $vanillaCtData.definitions) { [void]$vanillaContainerTypes.Add($d) }
    } catch {
        Write-Host "[WARN] Could not parse vanilla_container_types.json - vanilla container types will not be recognized: $_" -ForegroundColor Yellow
    }
}

# PrefabDefinition SubtypeIds shipped by vanilla Space Engineers itself (e.g. P26_HaulerWreck).
# A spawn group <Prefab SubtypeId="..."> naming one of these is valid even though no mod file
# defines it.
$vanillaPrefabs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$vanillaPrefabsPath = Join-Path $PSScriptRoot "vanilla_prefabs.json"
if (Test-Path $vanillaPrefabsPath) {
    try {
        $vanillaPrefabData = Get-Content -Raw $vanillaPrefabsPath | ConvertFrom-Json
        foreach ($d in $vanillaPrefabData.definitions) { [void]$vanillaPrefabs.Add($d) }
    } catch {
        Write-Host "[WARN] Could not parse vanilla_prefabs.json - vanilla prefabs will not be recognized: $_" -ForegroundColor Yellow
    }
}

# ContainerTypes.sbc files use vanilla SE's loot-table schema: a <ContainerType> block's
# own <Id><TypeId>ContainerTypeDefinition</TypeId><SubtypeId> is the real, referenceable
# definition; everything inside its nested <Items><Item><Id><SubtypeId> is a commodity
# item (ore/ingot/component id) that legitimately repeats across many container types and
# is never referenced by MES tags. These files get dedicated block-level parsing instead
# of the generic per-line SubtypeId scan below.
function Test-IsContainerTypesFile($file) {
    return $file.Name -match 'ContainerTypes'
}

# Prefab (and ship-blueprint) files embed whole grids: assembler queues, inventories,
# and component lists all carry nested <Id><SubtypeId> entries (SteelPlate, Uranium...)
# that repeat freely and are not MES profile definitions. Only the grid's own top-level
# PrefabDefinition / ShipBlueprintDefinition Id is registered for these files.
$gridDefIdPattern = '(?:MyObjectBuilder_)?(?:PrefabDefinition|ShipBlueprintDefinition)'
function Test-IsPrefabFile($file, $content) {
    if ($file.FullName -match '\\(Prefabs|StorePrefabs)(\\|$)') { return $true }
    return $content -match "<TypeId>$gridDefIdPattern</TypeId>|<Id\s[^>]*Type=`"$gridDefIdPattern`""
}

# Blanks out <!-- ... --> blocks (keeping newlines, so line numbers and indexes stay
# correct) so commented-out profiles are neither registered as definitions nor scanned
# for references.
function Remove-XmlComments([string]$content) {
    return [regex]::Replace($content, '(?s)<!--.*?-->', {
        param($m) [regex]::Replace($m.Value, '[^\r\n]', ' ')
    })
}

function Get-LineNumberAtIndex($content, $index) {
    return ($content.Substring(0, $index) -split "`n").Count
}

# Turns a reference name containing runtime tokens (e.g. 'Foo-{Faction}-Bar') into a
# regex that treats each token as a wildcard, so it can be checked against every known
# definition to see whether ANY substitution could ever resolve it.
function Convert-TokenRefToPattern([string]$name) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('^')
    $pos = 0
    foreach ($tm in [regex]::Matches($name, '\{[^}]+\}')) {
        if ($tm.Index -gt $pos) {
            [void]$sb.Append([regex]::Escape($name.Substring($pos, $tm.Index - $pos)))
        }
        [void]$sb.Append('.+')
        $pos = $tm.Index + $tm.Length
    }
    if ($pos -lt $name.Length) {
        [void]$sb.Append([regex]::Escape($name.Substring($pos)))
    }
    [void]$sb.Append('$')
    return $sb.ToString()
}

# Dictionaries to track definitions: Name -> @{ File = $file; Line = $line; ExactName = $name; Type = $type }
$definitions = @{}
$definitionsLower = @{}

# List of references: @{ Name = $name; File = $file; Line = $line; RefType = $refType }
$references = [System.Collections.Generic.List[PSObject]]::new()

# --- String-Tag broadcast system (separate from SubtypeId lookups; see MES source:
# TriggerProfile.Tags / EventProfile.Tags, TagParse.TagStringListCheck, and the
# ToggleTagTriggers/ManuallyActivateTrigger/ActivateEvent/ToggleEvents match loops in
# ActionSystem.cs / TriggerSystem.cs / EventActionExecution.cs). Two independent pools:
# a Trigger-tag string only ever matches other Trigger-declared tags, and an Event-tag
# string only ever matches other Event-declared tags. Matching is ordinal (case-sensitive)
# List<string>.Contains() everywhere - never fuzzy - and many profiles legitimately share
# one tag on purpose (a broadcast is meant to hit all of them), so these pools are NOT
# unique-key definitions and must never get a "duplicate definition" warning.
$triggerTagDefinitions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$eventTagDefinitions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
# [Tags:] declared on an [MES Event Template] containing a {token}: the template text is
# ReplaceText()'d per instance, so the declared tag becomes a concrete string at runtime.
# A literal broadcast that matches one of these as a wildcard is live, not undeclared.
$eventTemplateTagPatterns = [System.Collections.Generic.List[string]]::new()
$tagReferences = [System.Collections.Generic.List[PSObject]]::new()

# Zone-name namespace ([MES Zone] [PublicName:] vs [ZoneName:]/[ZoneNames:] references).
# Matching is ordinal, mirroring ZoneManager's zone.PublicName == name comparisons.
$zonePublicNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$zoneInternalNames = @{}
$zoneReferences = [System.Collections.Generic.List[PSObject]]::new()

# Owning SubtypeId -> profile header marker (e.g. "RivalAI Trigger"), used by the orphan
# pass to report only profile types that MES never activates on its own.
$profileHeaders = @{}

function Register-TagReference($names, $file, $refType, $pool, $tokenResolves) {
    if ($null -eq $names) { return }
    foreach ($n in $names) {
        if ([string]::IsNullOrWhiteSpace($n)) { continue }
        $tagReferences.Add([PSCustomObject]@{
            Name = $n.Trim()
            File = $file
            RefType = $refType
            Pool = $pool
            TokenResolves = $tokenResolves
        })
    }
}

function Register-Definition($name, $file, $line, $type) {
    if ([string]::IsNullOrWhiteSpace($name)) { return }
    $trimmed = $name.Trim()
    $lower = $trimmed.ToLowerInvariant()

    if ($definitions.ContainsKey($trimmed)) {
        # Duplicate definition warning
        Write-Host "[WARN] Duplicate definition of '$trimmed' in $($file.Name):$line (previously in $($definitions[$trimmed].File.Name):$($definitions[$trimmed].Line))" -ForegroundColor Yellow
    } else {
        $defObj = [PSCustomObject]@{
            File = $file
            Line = $line
            ExactName = $trimmed
            Type = $type
        }
        $definitions[$trimmed] = $defObj
        $definitionsLower[$lower] = $defObj
    }
}

# Set per Description block during the scan. [MES Event Template] / [MES Event Condition
# Template] / [MES Event Action Template] text is run through IdsReplacer.ReplaceText()
# with the instance's replace keys BEFORE its tags are parsed (Event.cs Profile getter and
# Event.Init), so a token anywhere in such a block can resolve - every reference it makes
# is token-aware regardless of RefType.
$script:blockIsTextTemplate = $false

# $tokenAware: $null = decide from RefType ($tokenAwareRefTypes in Pass 2); $true/$false =
# per-context override. $severity "Warn" is for references MES reads but that may be
# legitimate or inert when unresolved (see each call site).
function Register-Reference($names, $file, $line, $refType, $tokenAware = $null, $severity = "Error") {
    if ($null -eq $names) { return }
    if ($script:blockIsTextTemplate) { $tokenAware = $true }
    foreach ($n in $names) {
        if ([string]::IsNullOrWhiteSpace($n)) { continue }
        $trimmed = $n.Trim()
        if ($trimmed.Length -eq 0) { continue }
        $references.Add([PSCustomObject]@{
            Name = $trimmed
            File = $file
            Line = $line
            RefType = $refType
            TokenAware = $tokenAware
            Severity = $severity
        })
    }
}

function Parse-CsvTags($block, $tagName) {
    # MES allows some tags to either take a comma list on one line, OR be repeated on
    # separate lines within the same profile (e.g. GVK's [MES Loot] profiles list one
    # [ContainerTypes:X] per line rather than a single comma-separated tag). A single
    # -match only captures the first occurrence, so every occurrence must be collected.
    $results = [System.Collections.Generic.List[string]]::new()
    $tagMatches = [regex]::Matches($block, "\[$tagName\s*:\s*([^\]]+)\]")
    foreach ($tm in $tagMatches) {
        $val = $tm.Groups[1].Value.Trim()
        foreach ($v in ($val -split ',')) {
            $vTrim = $v.Trim()
            if ($vTrim.Length -gt 0) { $results.Add($vTrim) }
        }
    }
    return $results
}

# Scan pass 1: Collect definitions and references
foreach ($file in $sbcFiles) {
    $content = Remove-XmlComments ([System.IO.File]::ReadAllText($file.FullName))
    $isPrefab = Test-IsPrefabFile $file $content
    if ($isPrefab -and -not $IncludePrefabs) { continue }

    $lines = $content -split "`r?`n"
    $isContainerTypesFile = Test-IsContainerTypesFile $file

    if ($isPrefab) {
        # Only the grid's own PrefabDefinition/ShipBlueprintDefinition Id is a definition -
        # nested item/blueprint/component Ids are deliberately not registered (see
        # Test-IsPrefabFile).
        $gridIdMatches = [regex]::Matches($content, "(?s)<Id>\s*<TypeId>$gridDefIdPattern</TypeId>\s*<SubtypeId>([^<]+)</SubtypeId>|<Id\s[^>]*?Subtype=`"([^`"]+)`"[^>]*>")
        foreach ($gm in $gridIdMatches) {
            if ($gm.Groups[1].Success) {
                $subId = $gm.Groups[1].Value
            } elseif ($gm.Value -match "Type=`"$gridDefIdPattern`"") {
                $subId = $gm.Groups[2].Value
            } else { continue }
            Register-Definition $subId $file (Get-LineNumberAtIndex $content $gm.Index) "PrefabDefinition"
        }
    } elseif ($isContainerTypesFile) {
        # Only the ContainerType's own Id (TypeId=ContainerTypeDefinition) is a
        # definition - nested <Items><Item> commodity SubtypeIds are deliberately not
        # registered at all (see header comment).
        $ctMatches = [regex]::Matches($content, '(?s)<Id>\s*<TypeId>ContainerTypeDefinition</TypeId>\s*<SubtypeId>([^<]+)</SubtypeId>\s*</Id>')
        foreach ($cm in $ctMatches) {
            $subId = $cm.Groups[1].Value.Trim()
            $lineNum = Get-LineNumberAtIndex $content $cm.Index
            Register-Definition $subId $file $lineNum "ContainerTypeDefinition"
        }
    } else {
        # XML-level definitions: <SubtypeId> or <Prefab Subtype="...">
        $inId = $false
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            $lineNum = $i + 1
            if ($line -match '<Id>') { $inId = $true }

            # Check <SubtypeId>Foo</SubtypeId>. Only a SubtypeId inside a definition's own
            # <Id> element defines something; elsewhere it is a reference (e.g. a spawn
            # group's <Factions><SubtypeId>Unknown</SubtypeId></Factions>).
            if ($inId -and $line -match '<SubtypeId>([^<]+)</SubtypeId>') {
                $subId = $matches[1].Trim()
                Register-Definition $subId $file $lineNum "SubtypeId"
            }
            if ($line -match '</Id>') { $inId = $false }

            # Check <Id Type="..." Subtype="Foo" />
            if ($line -match '<Id\s+[^>]*Subtype="([^"]+)"') {
                $subId = $matches[1].Trim()
                Register-Definition $subId $file $lineNum "SubtypeAttr"
            }

            # Check Prefab references inside SpawnGroups: <Prefab SubtypeId="Foo">
            if ($line -match '<Prefab\s+[^>]*SubtypeId="([^"]+)"') {
                Register-Reference @($matches[1].Trim()) $file $lineNum "SpawnGroupPrefab"
            }

            # SpawnGroup <Prefab><Behaviour>: PrefabSpawner.cs copies it to
            # NpcData.BehaviorName. With [UseRivalAi:true], BehaviorBuilder.cs looks it up
            # in ProfileManager.BehaviorTemplates (exact TryGetValue; miss = "RivalAI Profile
            # Does Not Exist", RC gets no behavior). Without RivalAI it is handed to Keen's
            # drone AI (NpcData.cs SetDroneBehaviourFull), where a vanilla behavior name is
            # legitimate - so an unresolved name is a warning, not an error.
            if ($line -match '<Behaviour>([^<]+)</Behaviour>') {
                Register-Reference @($matches[1].Trim()) $file $lineNum "SpawnGroupBehaviour" $false "Warn"
            }
        }
    }

    # Description profile block references. The optional prefix captures the owning
    # SubtypeId (the <Id> directly before <Description>) so the block's header can be
    # recorded for the orphan pass.
    $descMatches = [System.Text.RegularExpressions.Regex]::Matches($content, '(?s)(?:<SubtypeId>([^<]+)</SubtypeId>\s*</Id>\s*)?<Description>(.*?)</Description>')
    foreach ($dm in $descMatches) {
        $block = $dm.Groups[2].Value
        if ($dm.Groups[1].Success) {
            $headerMatch = [regex]::Match($block, '\[([A-Za-z][A-Za-z ]*)\]')
            if ($headerMatch.Success) { $profileHeaders[$dm.Groups[1].Value.Trim()] = $headerMatch.Groups[1].Value }
        }
        $script:blockIsTextTemplate = $block -match '\[MES Event (Template|Condition Template|Action Template)\]'

        # --- String-Tag pool membership: which pool a [Tags:] declaration in THIS block
        # belongs to depends on the profile type marker present in the block (TriggerProfile
        # vs EventProfile are separate C# classes with separate Tags fields/pools).
        # [MES Event Template] instances build an EventProfile from the template text
        # (Event.cs Profile getter), so their [Tags:] join the Event-tag pool too.
        $isTriggerProfile = $block -match '\[(RivalAI|MES AI) Trigger\]'
        $isEventProfile = $block -match '\[MES Event( Template)?\]'
        $isMissionProfile = $block -match '\[MES Mission\]'
        # ActionReferenceProfile.cs (RivalAI/MES AI Action, live NpcData via ActionSystem.cs)
        # and EventActionReference.cs (MES Event Action, npcData=null) are SEPARATE C# classes
        # that happen to both declare ToggleEvent*/ResetEventCooldown* fields - confirmed by
        # reading both files directly. Same tag name, different token behavior depending on
        # which block it's declared in.
        $isRivalAIAction = $block -match '\[(RivalAI|MES AI) Action\]'
        if ($isTriggerProfile) {
            foreach ($t in (Parse-CsvTags $block 'Tags')) { [void]$triggerTagDefinitions.Add($t) }
        }
        if ($isEventProfile) {
            foreach ($t in (Parse-CsvTags $block 'Tags')) {
                if ($script:blockIsTextTemplate -and $t -match '\{[^}]+\}') {
                    $eventTemplateTagPatterns.Add((Convert-TokenRefToPattern $t))
                } else {
                    [void]$eventTagDefinitions.Add($t)
                }
            }
        }

        # Trigger-tag pool consumers - all confirmed to run through IdsReplacer with live
        # NpcData (RivalAI Behavior/Trigger Action context: ActionSystem.cs/TriggerSystem.cs).
        # These fields exist ONLY on ActionReferenceProfile.cs (confirmed no MES-Events
        # equivalent), so unlike Toggle/ResetEventCooldown below they don't need block-type
        # gating - they always token-resolve.
        Register-TagReference (Parse-CsvTags $block 'ManuallyActivatedTriggerTags') $file "ManuallyActivatedTriggerTags" "Trigger" $true
        Register-TagReference (Parse-CsvTags $block 'EnableTriggerTags') $file "EnableTriggerTags" "Trigger" $true
        Register-TagReference (Parse-CsvTags $block 'DisableTriggerTags') $file "DisableTriggerTags" "Trigger" $true
        Register-TagReference (Parse-CsvTags $block 'ResetTriggerCooldownTags') $file "ResetTriggerCooldownTags" "Trigger" $true

        # Event-tag pool consumers. [ActivateEventTags:] exists ONLY on the RivalAI side
        # (live NpcData, always token-resolves) - a cross-system bridge into MES Events.
        # [ToggleEventTags:]/[ResetEventCooldownTags:] are declared on BOTH
        # ActionReferenceProfile.cs (RivalAI/MES AI Action - wrapped in IdsReplacer at
        # ActionSystem.cs, token-resolves) AND EventActionReference.cs (MES Event Action -
        # npcData=null, NOT wrapped in IdsReplacer at EventActionExecution.cs, tokens dead) -
        # so which one applies depends on the block's own profile-type marker.
        # [IncreaseRunCountEventTags:] exists ONLY on the MES-Events side - always dead.
        Register-TagReference (Parse-CsvTags $block 'ActivateEventTags') $file "ActivateEventTags" "Event" $true
        Register-TagReference (Parse-CsvTags $block 'ToggleEventTags') $file "ToggleEventTags" "Event" $isRivalAIAction
        Register-TagReference (Parse-CsvTags $block 'ResetEventCooldownTags') $file "ResetEventCooldownTags" "Event" $isRivalAIAction
        Register-TagReference (Parse-CsvTags $block 'IncreaseRunCountEventTags') $file "IncreaseRunCountEventTags" "Event" $false

        # Name-based siblings of the tag broadcasts above - these ARE plain SubtypeId
        # lookups (not the Tag pool), so they reuse the existing SubtypeId reference system.
        # Both are confirmed to token-resolve via IdsReplacer (live NpcData, same call sites
        # as their *Tags siblings above) - given their own RefType rather than reusing
        # "Trigger"/generic, since a plain [Triggers:] reference does NOT token-resolve and
        # must not be silently exempted by sharing a token-aware RefType.
        Register-Reference (Parse-CsvTags $block 'ManuallyActivatedTriggerNames') $file 0 "ManuallyActivatedTriggerNames"
        Register-Reference (Parse-CsvTags $block 'ActivateEventIds') $file 0 "Event"

        # Remote Control / Behavior references
        Register-Reference (Parse-CsvTags $block 'Triggers') $file 0 "Trigger"
        Register-Reference (Parse-CsvTags $block 'TriggerGroups') $file 0 "TriggerGroup"
        Register-Reference (Parse-CsvTags $block 'AutopilotData') $file 0 "Autopilot"
        Register-Reference (Parse-CsvTags $block 'SecondaryAutopilotData') $file 0 "Autopilot"
        Register-Reference (Parse-CsvTags $block 'TertiaryAutopilotData') $file 0 "Autopilot"
        Register-Reference (Parse-CsvTags $block 'TargetData') $file 0 "Target"
        # WeaponSystem.cs accepts both spellings.
        Register-Reference (Parse-CsvTags $block 'WeaponSystem') $file 0 "WeaponSystem"
        Register-Reference (Parse-CsvTags $block 'WeaponsSystem') $file 0 "WeaponSystem"

        # Trigger references
        Register-Reference (Parse-CsvTags $block 'Conditions') $file 0 "Condition"
        Register-Reference (Parse-CsvTags $block 'Actions') $file 0 "Action"
        Register-Reference (Parse-CsvTags $block 'ElseActions') $file 0 "Action"
        Register-Reference (Parse-CsvTags $block 'ToggleWithTriggerProfile') $file 0 "Trigger"

        # Trigger-name toggles. Enable/Disable/ResetTriggerCooldownNames exist only on
        # ActionReferenceProfile.cs and go through TriggerSystem.ToggleTriggers(List), which
        # IdsReplacer.ReplaceId()s each name - token-aware. [DisableNamedTriggerOnSuccess:]
        # (TriggerProfile.cs) calls the string overload directly, no replace - static.
        # Either way the match is an exact == against triggers on the same behavior.
        Register-Reference (Parse-CsvTags $block 'EnableTriggerNames') $file 0 "TriggerName"
        Register-Reference (Parse-CsvTags $block 'DisableTriggerNames') $file 0 "TriggerName"
        Register-Reference (Parse-CsvTags $block 'ResetTriggerCooldownNames') $file 0 "TriggerName"
        # Aliases that write to the same lists (ActionReferenceProfile.cs tag dictionary).
        Register-Reference (Parse-CsvTags $block 'EnableTriggerIds') $file 0 "TriggerName"
        Register-Reference (Parse-CsvTags $block 'DisableTriggerIds') $file 0 "TriggerName"
        Register-Reference (Parse-CsvTags $block 'DisableNamedTriggerOnSuccess') $file 0 "TriggerNameStatic"

        # Condition references. [RequiredSpawnConditions:] is compared with == against the
        # NPC's spawn-conditions ProfileSubtypeId (ConditionProfile.cs) - a spawn-conditions
        # profile or, for inline conditions, the SpawnGroup's own name. Both are indexed.
        Register-Reference (Parse-CsvTags $block 'RequiredSpawnConditions') $file 0 "SpawnCondition"
        # PlayerCondition.ArePlayerConditionsMet: exact TryGetValue, no replace.
        Register-Reference (Parse-CsvTags $block 'PlayerConditionIds') $file 0 "PlayerCondition"
        Register-Reference (Parse-CsvTags $block 'LeadPlayerConditionIds') $file 0 "PlayerCondition"

        # [WaypointsToAdd:] -> ActionSystem.cs IdsReplacer.ReplaceId() then
        # EncounterWaypoint.CalculateWaypoint's exact WaypointProfiles lookup - token-aware.
        Register-Reference (Parse-CsvTags $block 'WaypointsToAdd') $file 0 "Waypoint"
        # [Waypoint:] is a WaypointProfiles reference only in Spawn and Command profiles
        # (BehaviorSpawnHelper.cs / CommandHelper.cs, both IdsReplacer.ReplaceId first). In a
        # [RivalAI Waypoint] profile the same tag is the waypoint-type enum (Static, ...).
        if ($block -match '\[(RivalAI|MES AI) (Spawn|Command)\]') {
            Register-Reference (Parse-CsvTags $block 'Waypoint') $file 0 "Waypoint"
        }
        # [NewBehavior:] -> CoreBehavior.ChangeBehavior exact BehaviorTemplates lookup.
        Register-Reference (Parse-CsvTags $block 'NewBehavior') $file 0 "Behavior"

        # Action references
        Register-Reference (Parse-CsvTags $block 'Spawner') $file 0 "Spawner"
        Register-Reference (Parse-CsvTags $block 'SpawnData') $file 0 "SpawnData"
        Register-Reference (Parse-CsvTags $block 'Chat') $file 0 "Chat"
        Register-Reference (Parse-CsvTags $block 'ChatData') $file 0 "ChatData"
        Register-Reference (Parse-CsvTags $block 'CommandProfileIds') $file 0 "CommandProfile"
        # Same dual-context split as ToggleEventTags/ResetEventCooldownTags above:
        # token-resolves only when declared inside a [RivalAI Action]/[MES AI Action] block.
        Register-Reference (Parse-CsvTags $block 'ToggleEventIds') $file 0 $(if ($isRivalAIAction) { "ToggleEvent" } else { "ToggleEventStatic" })
        Register-Reference (Parse-CsvTags $block 'ResetEventCooldownIds') $file 0 $(if ($isRivalAIAction) { "ResetEvent" } else { "ResetEventStatic" })
        Register-Reference (Parse-CsvTags $block 'SafeZoneProfile') $file 0 "SafeZone"
        Register-Reference (Parse-CsvTags $block 'StoreProfiles') $file 0 "Store"

        # Spawner references
        Register-Reference (Parse-CsvTags $block 'SpawnGroups') $file 0 "SpawnGroup"

        # SpawnGroup & Manipulation references (all exact TryGetValue lookups)
        Register-Reference (Parse-CsvTags $block 'SpawnConditionsProfiles') $file 0 "SpawnCondition"
        Register-Reference (Parse-CsvTags $block 'SpawnConditionGroups') $file 0 "SpawnConditionGroup"
        Register-Reference (Parse-CsvTags $block 'DerelictionProfiles') $file 0 "Dereliction"
        Register-Reference (Parse-CsvTags $block 'ManipulationProfiles') $file 0 "Manipulation"
        Register-Reference (Parse-CsvTags $block 'ManipulationGroups') $file 0 "ManipulationGroup"
        Register-Reference (Parse-CsvTags $block 'BlockReplacerProfileNames') $file 0 "BlockReplacement"
        Register-Reference (Parse-CsvTags $block 'LootProfiles') $file 0 "Loot"
        Register-Reference (Parse-CsvTags $block 'LootGroups') $file 0 "LootGroup"
        Register-Reference (Parse-CsvTags $block 'ReplenishProfiles') $file 0 "Replenishment"
        # TagParse.TagZoneConditionsProfileCheck: a miss is silently dropped from the list.
        Register-Reference (Parse-CsvTags $block 'ZoneConditions') $file 0 "ZoneConditions"

        # Zone names are their own namespace: every by-name lookup (ZoneManager.cs,
        # SpawnConditions.cs) compares zone.PublicName. [Name:] is stored but never read.
        if ($block -match '\[MES Zone\]') {
            foreach ($zn in (Parse-CsvTags $block 'PublicName')) { [void]$zonePublicNames.Add($zn) }
            foreach ($zn in (Parse-CsvTags $block 'Name')) { $zoneInternalNames[$zn] = $true }
        } else {
            foreach ($zoneTag in 'ZoneName', 'ZoneNames') {
                foreach ($zn in (Parse-CsvTags $block $zoneTag)) {
                    $zoneReferences.Add([PSCustomObject]@{ Name = $zn; File = $file; Tag = $zoneTag })
                }
            }
        }

        # Zone spawn-group lists (Zone.cs / ZoneManager.cs): literal names, no replace.
        # [RestrictedSpawnGroups:] is only read when [UseRestrictedSpawnGroups:true], so an
        # unresolved name in an inactive list is stale config, not a live bug.
        $restrictedSeverity = if ($block -match '\[UseRestrictedSpawnGroups:\s*true\s*\]') { "Error" } else { "Warn" }
        Register-Reference (Parse-CsvTags $block 'RestrictedSpawnGroups') $file 0 "ZoneSpawnGroup" $null $restrictedSeverity
        Register-Reference (Parse-CsvTags $block 'AllowedSpawnGroups') $file 0 "ZoneSpawnGroup"

        # Container-type / loot-table references (validated against local
        # ContainerType definitions, MES's shipped types, and vanilla SE's stock types)
        Register-Reference (Parse-CsvTags $block 'ContainerTypes') $file 0 "ContainerType"
        Register-Reference (Parse-CsvTags $block 'ContainerTypeAssignSubtypeId') $file 0 "ContainerType"
        Register-Reference (Parse-CsvTags $block 'AssignContainerTypesToAllCargo') $file 0 "ContainerType"
        Register-Reference (Parse-CsvTags $block 'ContainerTypeSubtypeIds') $file 0 "ContainerType"

        # Event references
        Register-Reference (Parse-CsvTags $block 'ConditionIds') $file 0 "EventCondition"
        Register-Reference (Parse-CsvTags $block 'PersistantConditionIds') $file 0 "EventCondition"
        Register-Reference (Parse-CsvTags $block 'PersistantEventConditionIds') $file 0 "EventCondition"
        # [MES Mission] [EventConditionIds:] - only read since MES 2.74.04 (Mission.cs).
        Register-Reference (Parse-CsvTags $block 'EventConditionIds') $file 0 "EventCondition"
        Register-Reference (Parse-CsvTags $block 'ActionIds') $file 0 "EventAction"
        Register-Reference (Parse-CsvTags $block 'TemplateEventIds') $file 0 "EventTemplate"

        # Contracts & missions. ContractBlockProfiles (ActionSystem.cs), MissionIds
        # (ContractBlockProfile.cs) and a mission's StoreProfileId (Mission.cs) are exact
        # lookups with no replace. InstanceEventGroupId is passed raw from RivalAI and MES
        # Event actions, but a [MES Mission] ReplaceText()s it with the mission's keys
        # (Mission.cs) - token-aware only there.
        Register-Reference (Parse-CsvTags $block 'ContractBlockProfiles') $file 0 "ContractBlock"
        Register-Reference (Parse-CsvTags $block 'MissionIds') $file 0 "Mission"
        Register-Reference (Parse-CsvTags $block 'StoreProfileId') $file 0 "Store" $false
        Register-Reference (Parse-CsvTags $block 'InstanceEventGroupId') $file 0 "EventTemplateGroup" $isMissionProfile
    }
}
$script:blockIsTextTemplate = $false

Write-Host "Total Definitions Indexed: $($definitions.Count)" -ForegroundColor Gray
Write-Host "Total References Checked: $($references.Count)" -ForegroundColor Gray
Write-Host ""

$errors = 0
$warnings = 0
$referencedNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

# Pass 2: Validate all references
foreach ($ref in $references) {
    $refName = $ref.Name
    $referencedNames.Add($refName) | Out-Null
    $refLower = $refName.ToLowerInvariant()

    # Skip vanilla / external engine presets or common keywords if applicable
    if ($refName -in @("true", "false", "None", "Default", "Primary", "Secondary")) { continue }
    if ($ref.RefType -eq "SpawnGroupPrefab" -and $SkipPrefabs) { continue }

    # Runtime tokens (e.g. {Faction}, {SpawnGroupName}) are substituted by IdsReplacer.cs -
    # or, for [SpawnGroups:] specifically inside MES Events, by a separate bespoke
    # {Faction}-only replace fed from [SpawnFactionTags:] - but ONLY for a small, fixed set
    # of reference types. Verified end-to-end against the MES C# source
    # (ActionSystem.cs, EventActionExecution.cs, SpawnGroupManager.cs): every substitution
    # path is a plain literal string.Replace(), and every downstream lookup is an ordinary
    # exact-match List.Contains()/dictionary lookup - there is no wildcard or pooled-name
    # matching anywhere in MES itself. A profile-name reference like [Actions:], [Triggers:],
    # [Conditions:], [TriggerGroups:], [ManipulationProfiles:], [LootProfiles:], or
    # [ContainerTypes:] has NO substitution mechanism at all - a token there is dead on
    # arrival, not a false positive, so it's flagged immediately regardless of whether some
    # unrelated definition happens to match the pattern.
    #
    # For the confirmed token-aware types below, the token is turned into a wildcard and
    # checked against every known definition: at least one match means the pattern is live
    # for some substitution (a real reference, not statically pinpointable further); zero
    # matches means the reference is dead no matter what gets substituted in - a genuine,
    # catchable typo/misconfiguration.
    #   - SpawnGroup   -> IdsReplacer (RivalAI Behavior Trigger Action, live NpcData)
    #                      AND a separate hardcoded {Faction}-only replace fed from
    #                      [SpawnFactionTags:] (MES Event SpawnEncounter action)
    #   - Store        -> IdsReplacer (RivalAI Behavior Trigger Action, live NpcData only -
    #                      NOT confirmed to resolve if this profile is instead invoked via
    #                      an MES Event's [ActionIds:] chain)
    #   - ToggleEvent, ResetEvent -> IdsReplacer (RivalAI Behavior Trigger Action, live
    #                      NpcData only - same RivalAI-only caveat as Store)
    #   - ManuallyActivatedTriggerNames, Event (from [ActivateEventIds:]) -> IdsReplacer,
    #                      same RivalAI Behavior/live-NpcData call sites as their *Tags
    #                      siblings in the string-Tag system below
    #   - TriggerName (Enable/Disable/ResetTriggerCooldownNames), Waypoint ([WaypointsToAdd:], Spawn/Command [Waypoint:]) ->
    #                      IdsReplacer.ReplaceId per name (TriggerSystem.ToggleTriggers /
    #                      ActionSystem AddWaypoints), live NpcData
    # A reference can also carry a per-context override ($ref.TokenAware): every reference
    # inside an [MES Event Template]/[... Condition Template]/[... Action Template] block is
    # token-aware (the whole template text is ReplaceText()'d per instance), and
    # [InstanceEventGroupId:] is token-aware only inside a [MES Mission].
    $tokenAwareRefTypes = @("SpawnGroup", "Store", "ToggleEvent", "ResetEvent", "ManuallyActivatedTriggerNames", "Event", "TriggerName", "Waypoint")
    $isTokenAware = $tokenAwareRefTypes -contains $ref.RefType
    if ($null -ne $ref.TokenAware) { $isTokenAware = $ref.TokenAware }
    if ($refName -match '\{[^}]+\}') {
        if (-not $isTokenAware) {
            Write-Host "[ERROR] Token in Static Reference ($($ref.RefType)): '$refName' in $($ref.File.Name) contains a runtime token, but MES has no substitution mechanism for $($ref.RefType) references (confirmed against source - always a literal SubtypeId lookup). This will always fail to find the profile, regardless of context." -ForegroundColor Red
            $errors++
            continue
        }

        $tokenPattern = Convert-TokenRefToPattern $refName
        # Every local definition the pattern could resolve to counts as used (orphan pass).
        $localMatches = @($definitions.Keys | Where-Object { $_ -match $tokenPattern })
        foreach ($lm in $localMatches) { [void]$referencedNames.Add($lm) }
        $wildcardMatch =
            ($localMatches.Count -gt 0) -or
            ($mesCoreDefinitions | Where-Object { $_ -match $tokenPattern } | Select-Object -First 1) -or
            ($vanillaContainerTypes | Where-Object { $_ -match $tokenPattern } | Select-Object -First 1)
        if ($wildcardMatch) {
            Write-Host "[INFO] Dynamic Token Reference ($($ref.RefType)): '$refName' in $($ref.File.Name) contains a runtime token that MES CAN substitute for this reference type; matches at least one real definition as a wildcard, so the pattern is live - not further verifiable statically, skipped." -ForegroundColor DarkCyan
        } else {
            Write-Host "[ERROR] Dead Token Pattern ($($ref.RefType)): '$refName' in $($ref.File.Name) does not match ANY defined profile even with its token(s) treated as a wildcard - this reference can never resolve to anything, no matter what gets substituted in!" -ForegroundColor Red
            $errors++
        }
        continue
    }

    # Built-in MES core profile (ships inside the MES mod itself, not this mod).
    if ($mesCoreDefinitions.Contains($refName)) { continue }

    # Stock vanilla SE container type (ContainerType references only).
    if ($ref.RefType -eq "ContainerType" -and $vanillaContainerTypes.Contains($refName)) { continue }

    # Stock vanilla SE prefab (spawn group <Prefab SubtypeId> references only).
    if ($ref.RefType -eq "SpawnGroupPrefab" -and $vanillaPrefabs.Contains($refName)) { continue }

    if (-not $definitionsLower.ContainsKey($refLower)) {
        if ($ref.Severity -eq "Warn") {
            $why = switch ($ref.RefType) {
                "SpawnGroupBehaviour" { "not a RivalAI Behavior in this mod or MES. With [UseRivalAi:true] the Remote Control gets no behavior; it is only valid if it names a vanilla Keen drone AI behavior." }
                "ZoneSpawnGroup" { "not a SpawnGroup. This list is inactive ([UseRestrictedSpawnGroups:true] is not set), so it has no effect until enabled - stale entry." }
                default { "not defined anywhere." }
            }
            Write-Host "[WARN] Unresolved Reference ($($ref.RefType)): '$refName' in $($ref.File.Name) is $why" -ForegroundColor Yellow
            $warnings++
        } else {
            Write-Host "[ERROR] Missing Reference ($($ref.RefType)): '$refName' referenced in $($ref.File.Name) is not defined anywhere!" -ForegroundColor Red
            $errors++
        }
    } elseif (-not $definitions.ContainsKey($refName)) {
        $actual = $definitionsLower[$refLower].ExactName
        Write-Host "[WARN] Case Mismatch ($($ref.RefType)): '$refName' in $($ref.File.Name) does not match definition '$actual' in $($definitionsLower[$refLower].File.Name)" -ForegroundColor Yellow
        $warnings++
    }
}

# Pass 2b: Validate string-Tag broadcast references (Trigger-tag and Event-tag pools are
# separate namespaces - see the Register-TagReference block above for why). Matching is
# ordinal/case-sensitive to mirror MES's own List<string>.Contains() semantics exactly.
Write-Host "Trigger Tags Declared: $($triggerTagDefinitions.Count) | Event Tags Declared: $($eventTagDefinitions.Count) | Tag References Checked: $($tagReferences.Count)" -ForegroundColor Gray
foreach ($tref in $tagReferences) {
    $tagName = $tref.Name
    # Plain assignment, not "$pool = if (...) { $set }": PowerShell enumerates a statement's
    # output, so an EMPTY HashSet would come back as $null and .Contains() would throw.
    $pool = $eventTagDefinitions
    $poolLabel = "Event-tag"
    if ($tref.Pool -eq "Trigger") {
        $pool = $triggerTagDefinitions
        $poolLabel = "Trigger-tag"
    }

    if ($tagName -match '\{[^}]+\}') {
        if (-not $tref.TokenResolves) {
            Write-Host "[ERROR] Token in Non-Resolving Tag ($($tref.RefType)): '$tagName' in $($tref.File.Name) contains a runtime token, but this tag field runs inside MES Events (npcData is null) with no IdsReplacer wrapping - confirmed against source (EventActionExecution.cs). The token never resolves, so this broadcast will always target a literal string containing '{...}' that no [Tags:] declaration can ever match." -ForegroundColor Red
            $errors++
            continue
        }
        $tokenPattern = Convert-TokenRefToPattern $tagName
        $wildcardMatch = $pool | Where-Object { $_ -match $tokenPattern } | Select-Object -First 1
        if ($wildcardMatch) {
            Write-Host "[INFO] Dynamic Token Tag Reference ($($tref.RefType)): '$tagName' in $($tref.File.Name) contains a runtime token resolved by IdsReplacer before matching; matches at least one declared $poolLabel as a wildcard, so the pattern is live - not further verifiable statically, skipped." -ForegroundColor DarkCyan
        } else {
            Write-Host "[ERROR] Dead Token Tag Pattern ($($tref.RefType)): '$tagName' in $($tref.File.Name) does not match ANY declared $poolLabel even with its token(s) treated as a wildcard - this broadcast can never hit anything, no matter what gets substituted in!" -ForegroundColor Red
            $errors++
        }
        continue
    }

    if (-not $pool.Contains($tagName)) {
        if ($tref.Pool -eq "Event" -and ($eventTemplateTagPatterns | Where-Object { $tagName -match $_ } | Select-Object -First 1)) {
            Write-Host "[INFO] Template Tag Match ($($tref.RefType)): '$tagName' in $($tref.File.Name) matches a tokenized [Tags:] on an [MES Event Template] (resolved per instance) - live, not further verifiable statically." -ForegroundColor DarkCyan
            continue
        }
        Write-Host "[ERROR] Undeclared Tag ($($tref.RefType)): '$tagName' in $($tref.File.Name) does not match any declared $poolLabel ([Tags:] on a matching profile) - this broadcast silently does nothing (MES's tag match is an exact List.Contains(), no error is logged)." -ForegroundColor Red
        $errors++
    }
}

# Pass 2c: Validate zone-name references against [MES Zone] [PublicName:] values. Only
# meaningful when the scan saw at least one zone; zones from other mods can't be seen, so
# an unknown name is a warning. A name that matches a zone's [Name:] instead is a known
# silent failure (the lookup never reads [Name:]), so that is an error.
if ($zonePublicNames.Count -gt 0 -or $zoneInternalNames.Count -gt 0) {
    Write-Host "Zone PublicNames Declared: $($zonePublicNames.Count) | Zone References Checked: $($zoneReferences.Count)" -ForegroundColor Gray
    foreach ($zref in $zoneReferences) {
        $zn = $zref.Name
        if ($zn -match '\{[^}]+\}' -or $zonePublicNames.Contains($zn)) { continue }
        if ($zoneInternalNames.ContainsKey($zn)) {
            Write-Host "[ERROR] Zone Referenced By [Name:] ($($zref.Tag)): '$zn' in $($zref.File.Name) matches a [MES Zone] [Name:], but MES looks zones up by [PublicName:] only (ZoneManager.cs) - this zone reference never matches anything." -ForegroundColor Red
            $errors++
        } else {
            Write-Host "[WARN] Unknown Zone ($($zref.Tag)): '$zn' in $($zref.File.Name) does not match the [PublicName:] of any [MES Zone] in the scanned files (fine only if the zone is defined in another mod)." -ForegroundColor Yellow
            $warnings++
        }
    }
}

# Pass 3: Check for orphans (optional)
if ($WarnOrphans) {
    # Only profile types that do nothing unless something references them (registered in
    # ProfileManager.cs as lookup tables). Self-activating roots - SpawnGroups, [MES Event],
    # [MES Zone], [MES Static Encounter], [MES Weapon Mod Rules], [MES Suit Upgrades],
    # prefabs, etc. - are legitimately unreferenced and never reported.
    $referenceOnlyHeaders = @(
        "RivalAI Trigger", "MES AI Trigger", "RivalAI TriggerGroup", "MES AI TriggerGroup",
        "RivalAI Action", "MES AI Action", "RivalAI Condition", "MES AI Condition",
        "RivalAI Chat", "MES AI Chat", "RivalAI Spawn", "MES AI Spawn",
        "RivalAI Target", "MES AI Target", "RivalAI Autopilot", "MES AI Autopilot",
        "RivalAI Waypoint", "MES AI Waypoint", "RivalAI Weapons", "MES AI Weapons",
        "RivalAI Command", "MES AI Command", "RivalAI Behavior", "Rival AI Behavior", "MES AI Behavior",
        "MES Event Action", "MES Event Condition", "MES Event Action Template",
        "MES Event Condition Template", "MES Event Template", "MES Event TemplateGroup",
        "MES Mission", "MES Contract Block", "MES Store", "MES Loot", "MES Loot Group",
        "MES Manipulation", "MES Manipulation Group", "MES Spawn Conditions",
        "MES Spawn Conditions Group", "MES Zone Conditions", "MES Block Replacement",
        "MES Dereliction", "MES Replenishment", "MES SafeZone", "MES Player Condition"
    )
    $orphanCount = 0
    foreach ($defKey in ($definitions.Keys | Sort-Object)) {
        if ($referencedNames.Contains($defKey)) { continue }
        $header = $profileHeaders[$defKey]
        if ($null -eq $header -or $referenceOnlyHeaders -notcontains $header) { continue }
        $def = $definitions[$defKey]
        Write-Host "[INFO] Potentially Unused Profile ($header): '$defKey' in $($def.File.Name):$($def.Line)" -ForegroundColor DarkGray
        $orphanCount++
    }
    Write-Host "Potentially unused profiles: $orphanCount (Block Replacement / Loot profiles may also be referenced from MES world config, which this audit cannot see)." -ForegroundColor Gray
}

Write-Host ""
if ($errors -eq 0 -and $warnings -eq 0) {
    Write-Host "All profile cross-references verified successfully!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "Cross-Reference Audit Complete: $errors error(s), $warnings warning(s)." -ForegroundColor $(if ($errors -gt 0) { "Red" } else { "Yellow" })
    if ($errors -gt 0) { exit 1 }
}

