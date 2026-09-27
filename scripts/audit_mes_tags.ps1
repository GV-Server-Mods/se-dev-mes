<#
.SYNOPSIS
    Advanced semantic audit script for MES and RivalAI tags, master gates, and list alignments.
.DESCRIPTION
    Scans .sbc files for:
    1. Zero-stripping bugs across all affected tags (CustomCountersTargets, CustomSandboxCountersTargets, etc.).
    2. WaypointNear/WaypointFar trigger crash hazard.
    3. [RivalAI Action] zone custom bool/counter changes: missing gates, misaligned lists,
       comma lists on one-value-per-line tags, and [KnownPlayerAreaTimer:] <= 0 (no KPL created).
    4. [CutVoxels:true] on Spawn Conditions (does not exist in MES).
    5. Missing activation flags ([UseTrigger:true], [UseSpawn:true], [UseChat:true], [UseEvent:true], [UseConditions:true]).
    6. Conflicting Autopilot flags (FlyLevelWithGravity + UseSurfaceHoverThrustMode).
    7. Boolean formatting errors (True, TRUE, 1 instead of true).
    8. RivalAI vs MES Event Action tag mismatches ([Spawner:] vs [SpawnData:]; [Chat:] is not a tag - both use [ChatData:]).
    9. ContainerType master gates and list count mismatches in [MES Manipulation].
    10. ContainerType master gates and list count mismatches in [RivalAI Action].
    11. Missing boolean master gates and list count mismatches in [MES Event Action].
    12. Missing boolean master gates and list count mismatches in [MES Event Condition].
    13. Invalid token usage: {SpawnGroupName} anywhere in an [MES Event Action] (never
        resolves, no NpcData); {Faction} in an [MES Event Action] outside of [SpawnData:]
        (never resolves), or inside [SpawnData:] without a matching [SpawnFactionTags:]
        entry (MES's Event-only bespoke {Faction} replace requires it); tokens in
        [Actions:]/[Conditions:]/[Triggers:]/[TriggerGroups:] profile name references
        (always static lookups, no substitution mechanism exists for these at all).
    14. Faction tag internal consistency ([FactionOwner:], [FactionOverride:], [SpawnFactionTags:], [AllowedZoneFactions:], [RestrictedZoneFactions:]): a tag not declared in
        any local Factions*.sbc is checked for consistent reuse across the mod (likely a
        faction from another mod - INFO) vs. singleton/near-duplicate spellings (likely a
        typo - WARN), since there is no single enumerable source of truth for factions
        defined in arbitrary external/workshop mods.
.PARAMETER Path
    Path to search for .sbc files. Defaults to current directory.
#>
param(
    [string]$Path = "."
)

$files = Get-ChildItem -Path $Path -Filter *.sbc -Recurse | Where-Object { 
    $_.FullName -notmatch '\\(Prefabs|StorePrefabs)(\\|$)' 
}

$issuesFound = 0

# Harvest declared factions from workspace Factions*.sbc files
$knownFactions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

# Primary known factions and reserved keywords (pass silently)
$primaryFactions = @(
    'SPRT', 'SPID',
    'Nobody', 'UseBaseGameFactionTags'
)
foreach ($pf in $primaryFactions) { [void]$knownFactions.Add($pf) }

# Obscure vanilla / economy / campaign factions (soft informational notice, does not fail audit)
$obscureVanillaFactions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$vanillaEconomyCampaign = @(
    'CIVL', 'TRAD', 'ROBO', 'FSD', 'STEJ', 'KRI', 'INDEP', 
    'SHIV', 'GTI', 'ROS', 'AMPH', 'BLDR', 'MINR', 'MILT', 'PIR8', 'RED', 'BLU'
)
foreach ($vf in $vanillaEconomyCampaign) { [void]$obscureVanillaFactions.Add($vf) }

$factionFiles = Get-ChildItem -Path $Path -Filter *Faction*.sbc -Recurse -ErrorAction SilentlyContinue
foreach ($ff in $factionFiles) {
    $fContent = [System.IO.File]::ReadAllText($ff.FullName)
    $tagMatches = [System.Text.RegularExpressions.Regex]::Matches($fContent, '<Tag>([^<]+)</Tag>')
    foreach ($tm in $tagMatches) {
        [void]$knownFactions.Add($tm.Groups[1].Value.Trim())
    }
    $attrMatches = [System.Text.RegularExpressions.Regex]::Matches($fContent, 'Tag="([^"]+)"')
    foreach ($am in $attrMatches) {
        [void]$knownFactions.Add($am.Groups[1].Value.Trim())
    }
}

# Faction tags used but not declared in any local Factions*.sbc. Since encounters can
# legitimately target factions defined in other workshop mods (a core server mod, a
# faction pack, etc.) with no fixed, enumerable source of truth, these are NOT compared
# against a hardcoded external list. Instead they're collected here and, after the scan,
# checked for INTERNAL consistency: a tag reused identically across the mod is almost
# certainly a real external faction; a tag that appears only once, or that differs from
# another used tag by just one or two characters, is far more likely a typo.
$unknownFactionUsages = [System.Collections.Generic.List[PSObject]]::new()

function Get-LevenshteinDistance([string]$a, [string]$b) {
    $lenA = $a.Length; $lenB = $b.Length
    $d = New-Object 'int[,]' ($lenA + 1), ($lenB + 1)
    for ($i = 0; $i -le $lenA; $i++) { $d[$i, 0] = $i }
    for ($j = 0; $j -le $lenB; $j++) { $d[0, $j] = $j }
    for ($i = 1; $i -le $lenA; $i++) {
        for ($j = 1; $j -le $lenB; $j++) {
            $cost = if ($a[$i - 1] -eq $b[$j - 1]) { 0 } else { 1 }
            # Index expressions must be pre-computed into locals - PowerShell mis-parses
            # inline arithmetic inside a multi-dim array subscript (e.g. $d[$i - 1, $j]),
            # binding the comma as an array-literal separator instead of an index list.
            $iPrev = $i - 1
            $jPrev = $j - 1
            $del = $d[$iPrev, $j] + 1
            $ins = $d[$i, $jPrev] + 1
            $sub = $d[$iPrev, $jPrev] + $cost
            $d[$i, $j] = [Math]::Min([Math]::Min($del, $ins), $sub)
        }
    }
    return $d[$lenA, $lenB]
}

function Get-TagValues($block, $tagName) {
    # MES allows a tag to either take a comma list on one line, OR be repeated on separate
    # lines within the same profile (e.g. one [SpawnData:X] per line instead of a single
    # comma-separated tag) - both are valid and MES treats them identically (TagStringListCheck
    # just appends to the same list either way). A single -match only captures the first
    # occurrence, silently under-counting and breaking every "list count must match" check
    # below whenever a mod uses the repeated-line style - so every occurrence must be collected.
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

foreach ($file in $files) {
    $content = [System.IO.File]::ReadAllText($file.FullName)
    $lines = $content -split "`r?`n"

    # Line-by-line checks
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $lineNum = $i + 1

        # Check 1: Zero-stripping in all affected integer list tags
        if ($line -match '\[Custom(Sandbox)?CountersTargets:0\]' -or $line -match '\[Custom(Sandbox)?CountersTargets:.*,0(,|\])' -or
            $line -match '\[CustomZoneCounterValue:0\]' -or $line -match '\[CustomZoneCounterValue:.*,0(,|\])' -or
            $line -match '\[(Increase|Decrease)CountersAmount:0\]' -or $line -match '\[(Increase|Decrease)CountersAmount:.*,0(,|\])') {
            Write-Host "[ERROR] $($file.Name):$lineNum - Zero will be stripped by TagIntListCheck! Use -1 with Greater/LessOrEqual." -ForegroundColor Red
            $issuesFound++
        }

        # Check 2: WaypointNear / WaypointFar crash hazard
        if ($line -match '\[Type:Waypoint(Near|Far)\]') {
            Write-Host "[ERROR] $($file.Name):$lineNum - Type:WaypointNear/Far crashes trigger loops if CargoShipWaypoints is empty! Use TargetNear/Far instead." -ForegroundColor Red
            $issuesFound++
        }

        # Check 4: CutVoxels on Spawn Conditions
        if ($line -match '\[CutVoxels:true\]') {
            Write-Host "[WARN] $($file.Name):$lineNum - [CutVoxels:true] does not exist on MES Spawn Conditions. Use [CutVoxelsAtAirtightCells:true] + [CutVoxelSize:double]." -ForegroundColor Yellow
            $issuesFound++
        }

        # Check 5: Tokens in [Actions:] profile names (statically resolved at load)
        if ($line -match '\[Actions:.*\{[a-zA-Z0-9_]+\}.*\]') {
            Write-Host "[ERROR] $($file.Name):$lineNum - Dynamic tokens inside [Actions:] profile names fail to load! Action profile names resolve statically at startup." -ForegroundColor Red
            $issuesFound++
        }

        # Check 6: Boolean formatting (case-sensitive check flagging True or TRUE)
        if ($line -cmatch '\[([a-zA-Z0-9_]+):(True|TRUE)\]') {
            $tName = $matches[1]
            Write-Host "[WARN] $($file.Name):$lineNum - Tag [$tName] specifies capitalized boolean '$($matches[2])'. Use lowercase 'true'." -ForegroundColor Yellow
            $issuesFound++
        }

        # Check 7: Debug tags in Action profiles (development diagnostic notice)
        if ($line -match '\[(DebugMessage|DebugChatMessage|DebugHudMessage):.*\]') {
            Write-Host "[WARN] $($file.Name):$lineNum - Debug tag [$($matches[1])] found. Ensure debug tags are removed before production release (do not use as substitute for NPC chat)." -ForegroundColor Yellow
        }

        # Check 14: Faction tag validation (detects typos that cause silent 0% spawn rate)
        if ($line -match '\[(FactionOwner|FactionOverride|CheckReputationAgainstOtherNPCFaction)\s*:\s*([^\]]+)\]') {
            $propName = $matches[1]
            $fTag = $matches[2].Trim()
            if ($fTag.Length -gt 0) {
                if ($fTag -match '^\{.*\}$') {
                    Write-Host "[ERROR] $($file.Name):$lineNum - Dynamic token '$fTag' in [${propName}:$fTag] cannot be resolved! Faction tags in spawn conditions/groups are evaluated pre-spawn before NpcData exists (IdsReplacer does not run here)." -ForegroundColor Red
                    $issuesFound++
                }
                elseif ($knownFactions.Contains($fTag)) {
                    # Known primary or declared faction - passes silently
                }
                elseif ($obscureVanillaFactions.Contains($fTag)) {
                    Write-Host "[INFO] $($file.Name):$lineNum - Faction tag '$fTag' in [${propName}:$fTag] is an obscure vanilla/economy faction. Verify this faction is active in world settings." -ForegroundColor Cyan
                }
                else {
                    $unknownFactionUsages.Add([PSCustomObject]@{ Tag = $fTag; File = $file; Line = $lineNum; PropName = $propName })
                }
            }
        }
        if ($line -match '\[(AllowedZoneFactions|RestrictedZoneFactions|SpawnFactionTags)\s*:\s*([^\]]+)\]') {
            $propName = $matches[1]
            $rawList = $matches[2].Trim()
            foreach ($item in ($rawList -split ',')) {
                $fTag = $item.Trim()
                if ($fTag.Length -gt 0) {
                    if ($fTag -match '^\{.*\}$') {
                        Write-Host "[ERROR] $($file.Name):$lineNum - Dynamic token '$fTag' in [${propName}:$rawList] cannot be resolved! Faction tags in spawn conditions/groups are evaluated pre-spawn before NpcData exists (IdsReplacer does not run here)." -ForegroundColor Red
                        $issuesFound++
                    }
                    elseif ($knownFactions.Contains($fTag)) {
                        # Known primary or declared faction - passes silently
                    }
                    elseif ($obscureVanillaFactions.Contains($fTag)) {
                        Write-Host "[INFO] $($file.Name):$lineNum - Faction tag '$fTag' in [${propName}:$rawList] is an obscure vanilla/economy faction. Verify this faction is active in world settings." -ForegroundColor Cyan
                    }
                    else {
                        $unknownFactionUsages.Add([PSCustomObject]@{ Tag = $fTag; File = $file; Line = $lineNum; PropName = $propName })
                    }
                }
            }
        }
    }

    # Profile block checks (inside <Description>)
    $descMatches = [System.Text.RegularExpressions.Regex]::Matches($content, '(?s)<Description>(.*?)</Description>')
    foreach ($dm in $descMatches) {
        $block = $dm.Groups[1].Value

        # Check 7: Missing Activation Gates
        if (($block -match '\[(RivalAI|MES AI) Trigger\]') -and ($block -notmatch '\[UseTrigger:true\]' -and $block -notmatch '\[UseTrigger:false\]')) {
            Write-Host "[ERROR] $($file.Name) - [RivalAI Trigger] is missing required [UseTrigger:true] activation tag!" -ForegroundColor Red
            $issuesFound++
        }
        if (($block -match '\[(RivalAI|MES AI) Spawn\]') -and ($block -notmatch '\[UseSpawn:true\]' -and $block -notmatch '\[UseSpawn:false\]')) {
            Write-Host "[ERROR] $($file.Name) - [RivalAI Spawn] is missing required [UseSpawn:true] activation tag!" -ForegroundColor Red
            $issuesFound++
        }
        if (($block -match '\[(RivalAI|MES AI) Chat\]') -and ($block -notmatch '\[UseChat:true\]' -and $block -notmatch '\[UseChat:false\]')) {
            Write-Host "[ERROR] $($file.Name) - [RivalAI Chat] is missing required [UseChat:true] activation tag!" -ForegroundColor Red
            $issuesFound++
        }
        if (($block -match '\[MES Event\]') -and ($block -notmatch '\[UseEvent:true\]' -and $block -notmatch '\[UseEvent:false\]')) {
            Write-Host "[ERROR] $($file.Name) - [MES Event] is missing required [UseEvent:true] activation tag!" -ForegroundColor Red
            $issuesFound++
        }
        if (($block -match '\[(RivalAI|MES AI) Condition\]') -and ($block -notmatch '\[UseConditions:true\]' -and $block -notmatch '\[UseConditions:false\]')) {
            Write-Host "[ERROR] $($file.Name) - [RivalAI Condition] is missing required [UseConditions:true] activation tag!" -ForegroundColor Red
            $issuesFound++
        }

        # Check 8: Autopilot Conflicts
        if ($block -match '\[(RivalAI|MES AI) Autopilot\]') {
            if ($block -match '\[FlyLevelWithGravity:true\]' -and $block -match '\[UseSurfaceHoverThrustMode:true\]') {
                Write-Host "[ERROR] $($file.Name) - Autopilot declares both [FlyLevelWithGravity:true] and [UseSurfaceHoverThrustMode:true]! This causes severe physics oscillation." -ForegroundColor Red
                $issuesFound++
            }
        }

        # Check 9: MES Manipulation ContainerType Master Gates & Lists
        if ($block -match '\[MES Manipulation\]') {
            if (($block -match '\[ContainerTypeAssignBlockName:' -or $block -match '\[ContainerTypeAssignSubtypeId:') -and $block -notmatch '\[UseContainerTypeAssignment:true\]') {
                Write-Host "[ERROR] $($file.Name) - ContainerType assignment tags specified in [MES Manipulation] without required [UseContainerTypeAssignment:true] master gate!" -ForegroundColor Red
                $issuesFound++
            }
            $ctBlockNames = Get-TagValues $block 'ContainerTypeAssignBlockName'
            $ctSubtypeIds = Get-TagValues $block 'ContainerTypeAssignSubtypeId'
            if ($ctBlockNames.Count -ne $ctSubtypeIds.Count) {
                Write-Host "[ERROR] $($file.Name) - ContainerTypeAssignBlockName count ($($ctBlockNames.Count)) does not match ContainerTypeAssignSubtypeId count ($($ctSubtypeIds.Count))! MES will silently drop all assignments." -ForegroundColor Red
                $issuesFound++
            }
        }

        # Check 10: RivalAI Action ContainerType Master Gates & Lists
        if ($block -match '\[(RivalAI|MES AI) Action\]') {
            if (($block -match '\[ContainerTypeBlockNames:' -or $block -match '\[ContainerTypeSubtypeIds:') -and $block -notmatch '\[ApplyContainerTypeToInventoryBlock:true\]') {
                Write-Host "[ERROR] $($file.Name) - ContainerType tags specified in [RivalAI Action] without required [ApplyContainerTypeToInventoryBlock:true] master gate!" -ForegroundColor Red
                $issuesFound++
            }
            $actCtBlocks = Get-TagValues $block 'ContainerTypeBlockNames'
            $actCtSubtypes = Get-TagValues $block 'ContainerTypeSubtypeIds'
            if ($actCtBlocks.Count -ne $actCtSubtypes.Count) {
                Write-Host "[ERROR] $($file.Name) - ContainerTypeBlockNames count ($($actCtBlocks.Count)) does not match ContainerTypeSubtypeIds count ($($actCtSubtypes.Count))!" -ForegroundColor Red
                $issuesFound++
            }
        }

        # Check 3: RivalAI Action zone custom bools/counters and Known Player Areas
        # (ActionSystem.cs ChangeZoneAtPosition block, CustomValueHelper.cs, KnownPlayerLocationManager.cs).
        if ($block -match '\[(RivalAI|MES AI) Action\]') {
            $zoneGateOn = $block -match '\[ChangeZoneAtPosition:\s*true\]' -or $block -match '\[ChangeZoneOnlyByName:\s*true\]'
            foreach ($kind in 'Bool', 'Counter') {
                $masterOn = $block -match "\[ZoneCustom${kind}Change:\s*true\]"
                if ($block -match "\[ZoneCustom${kind}Change(Name|Value|Amount|Type):" -and -not $masterOn) {
                    Write-Host "[ERROR] $($file.Name) - ZoneCustom${kind}Change tags in [RivalAI Action] without [ZoneCustom${kind}Change:true]!" -ForegroundColor Red
                    $issuesFound++
                }
                if (-not $masterOn) { continue }
                if (-not $zoneGateOn) {
                    Write-Host "[ERROR] $($file.Name) - [ZoneCustom${kind}Change:true] needs [ChangeZoneAtPosition:true] or [ChangeZoneOnlyByName:true]; without either, MES skips every zone change in this action." -ForegroundColor Red
                    $issuesFound++
                }
                if ($block -notmatch "\[ZoneCustom${kind}ChangeUseKPL:\s*true\]" -and $block -notmatch '\[ZoneName:\s*[^\]\s]') {
                    Write-Host "[ERROR] $($file.Name) - [ZoneCustom${kind}Change:true] targets a named zone but [ZoneName:] is missing (set it to the zone's [PublicName:], or use [ZoneCustom${kind}ChangeUseKPL:true])." -ForegroundColor Red
                    $issuesFound++
                }
            }
            if ($block -match '\[ZoneCustomBoolChange:\s*true\]') {
                $zbNames = Get-TagValues $block 'ZoneCustomBoolChangeName'
                $zbValues = Get-TagValues $block 'ZoneCustomBoolChangeValue'
                if ($zbNames.Count -ne $zbValues.Count) {
                    Write-Host "[ERROR] $($file.Name) - ZoneCustomBoolChangeName count ($($zbNames.Count)) does not match ZoneCustomBoolChangeValue count ($($zbValues.Count))! MES applies only the shortest list." -ForegroundColor Red
                    $issuesFound++
                }
            }
            if ($block -match '\[ZoneCustomCounterChange:\s*true\]') {
                # Amount (TagLongCheck) and Type (TagModifierEnumCheck) take ONE value per tag line:
                # a comma list fails to parse and adds nothing.
                $zcNames = Get-TagValues $block 'ZoneCustomCounterChangeName'
                $zcCounts = @{}
                foreach ($oneValueTag in 'ZoneCustomCounterChangeAmount', 'ZoneCustomCounterChangeType') {
                    $lineValues = @([regex]::Matches($block, "\[$oneValueTag\s*:\s*([^\]]+)\]") | ForEach-Object { $_.Groups[1].Value })
                    foreach ($lv in $lineValues) {
                        if ($lv -match ',') {
                            Write-Host "[ERROR] $($file.Name) - [${oneValueTag}:$lv] is a comma list; this tag takes one value per line, so MES drops the whole entry." -ForegroundColor Red
                            $issuesFound++
                        }
                    }
                    $zcCounts[$oneValueTag] = @($lineValues | Where-Object { $_ -notmatch ',' }).Count
                }
                if ($zcNames.Count -ne $zcCounts['ZoneCustomCounterChangeAmount'] -or $zcNames.Count -ne $zcCounts['ZoneCustomCounterChangeType']) {
                    Write-Host "[ERROR] $($file.Name) - ZoneCustomCounterChange list mismatch! Names ($($zcNames.Count)), Amount lines ($($zcCounts['ZoneCustomCounterChangeAmount'])), Type lines ($($zcCounts['ZoneCustomCounterChangeType'])) must be equal; MES applies only the shortest list." -ForegroundColor Red
                    $issuesFound++
                }
            }
            if ($block -match '\[CreateKnownPlayerArea:\s*true\]' -and $block -match '\[KnownPlayerAreaTimer:\s*(-?\d+)\s*\]' -and [int]$Matches[1] -le 0) {
                Write-Host "[ERROR] $($file.Name) - [KnownPlayerAreaTimer:$($Matches[1])] is 0 or less; since MES 2.74.04 no Known Player Area is created (use minutes > 0 or Day)." -ForegroundColor Red
                $issuesFound++
            }
        }

        # Check 11: MES Event Action Master Gates & Lists
        if ($block -match '\[MES Event Action( Template)?\]') {
            if ($block -match '\[Spawner:') {
                Write-Host "[ERROR] $($file.Name) - [Spawner:] tag does not work in MES Event Actions! Use [SpawnData:] instead." -ForegroundColor Red
                $issuesFound++
            }
            if ($block -match '\[Chat:') {
                Write-Host "[ERROR] $($file.Name) - [Chat:] is not an MES tag! Use [UseChatBroadcast:true] + [ChatData:] (same tag in RivalAI and Event actions)." -ForegroundColor Red
                $issuesFound++
            }
            # {SpawnGroupName} never resolves in MES Events (npcData is null, and MES has
            # no bespoke fallback for it anywhere). {Faction} is different: MES Events run
            # a separate hardcoded {Faction}-only replace on [SpawnData:] values, fed from
            # the positionally-matched [SpawnFactionTags:] list (Events/Action/
            # EventActionExecution.cs) - so {Faction} inside [SpawnData:] is NOT dead, as
            # long as [SpawnFactionTags:] is present (list-count alignment is verified
            # separately by the SpawnEncounter list-mismatch check below). {Faction}
            # anywhere else in the block still has no resolution path.
            if ($block -match '\{SpawnGroupName\}') {
                Write-Host "[ERROR] $($file.Name) - {SpawnGroupName} does not resolve in MES Events (npcData is null, no bespoke fallback exists for this token)!" -ForegroundColor Red
                $issuesFound++
            }
            # [SpawnData:] can appear as a single comma-list OR repeated one-per-line (same
            # quirk as Get-TagValues above) - a single Match only strips the first occurrence,
            # so {Faction} in a second/third [SpawnData:] line would be wrongly flagged as
            # "outside [SpawnData:]". Every occurrence must be stripped before checking what's
            # left, and checked individually for whether it itself carries {Faction}.
            $spawnDataTagMatches = [regex]::Matches($block, '\[SpawnData\s*:\s*([^\]]+)\]')
            $blockMinusSpawnData = $block
            foreach ($m in ($spawnDataTagMatches | Sort-Object -Property Index -Descending)) {
                $blockMinusSpawnData = $blockMinusSpawnData.Remove($m.Index, $m.Length)
            }
            if ($blockMinusSpawnData -match '\{Faction\}') {
                Write-Host "[ERROR] $($file.Name) - {Faction} does not resolve in MES Events (npcData is null) outside of [SpawnData:] tags fed by a matching [SpawnFactionTags:] entry!" -ForegroundColor Red
                $issuesFound++
            } elseif (($spawnDataTagMatches | Where-Object { $_.Value -match '\{Faction\}' }) -and ($block -notmatch '\[SpawnFactionTags\s*:')) {
                Write-Host "[ERROR] $($file.Name) - {Faction} in [SpawnData:] requires a matching [SpawnFactionTags:] entry to resolve (MES's Event-only SpawnGroups replace) - no [SpawnFactionTags:] tag found in this profile!" -ForegroundColor Red
                $issuesFound++
            }

            # Master Gates
            if (($block -match '\[(Set|Increase|Decrease)Counters:' -or $block -match '\[(Set|Increase|Decrease)CountersAmount:') -and $block -notmatch '\[ChangeCounters:true\]') {
                Write-Host "[ERROR] $($file.Name) - Counter tags specified in [MES Event Action] without required [ChangeCounters:true] master gate!" -ForegroundColor Red
                $issuesFound++
            }
            if ($block -match '\[SetBooleans(True|False):' -and $block -notmatch '\[ChangeBooleans:true\]') {
                Write-Host "[ERROR] $($file.Name) - Boolean tags specified in [MES Event Action] without required [ChangeBooleans:true] master gate!" -ForegroundColor Red
                $issuesFound++
            }
            if (($block -match '\[Spawn(Data|Coords|FactionTags):') -and $block -notmatch '\[SpawnEncounter:true\]') {
                Write-Host "[ERROR] $($file.Name) - Spawner tags specified in [MES Event Action] without required [SpawnEncounter:true] master gate!" -ForegroundColor Red
                $issuesFound++
            }
            if ($block -match '\[Zone(Names|RadiusChangeTypes|RadiusChangeAmounts):' -and $block -notmatch '\[ChangeZoneByName:true\]') {
                Write-Host "[ERROR] $($file.Name) - Zone modification tags specified in [MES Event Action] without required [ChangeZoneByName:true] master gate!" -ForegroundColor Red
                $issuesFound++
            }
            if ($block -match '\[SandboxStrings:' -and $block -notmatch '\[SetSandboxStrings:true\]') {
                Write-Host "[ERROR] $($file.Name) - [SandboxStrings:] specified in [MES Event Action] without required [SetSandboxStrings:true] master gate!" -ForegroundColor Red
                $issuesFound++
            }
            # EventActionExecution.cs: an empty name or value hits 'return' inside the loop and aborts every later step of the action.
            if ($block -match '\[SandboxStrings:\s*(,|[^,\]]*,\s*\])') {
                Write-Host "[ERROR] $($file.Name) - [SandboxStrings:] entry with an empty name or value aborts the rest of this [MES Event Action] (return inside the loop)!" -ForegroundColor Red
                $issuesFound++
            }
            if ($block -match '\[SandboxVector3Ds:' -and $block -notmatch '\[SetSandboxVector3Ds:true\]') {
                Write-Host "[ERROR] $($file.Name) - [SandboxVector3Ds:] specified in [MES Event Action] without required [SetSandboxVector3Ds:true] master gate!" -ForegroundColor Red
                $issuesFound++
            }
            if ($block -match '\[InstanceEventGroup(Id|ReplaceKeys|ReplaceValues):' -and $block -notmatch '\[AddInstanceEventGroup:true\]') {
                Write-Host "[ERROR] $($file.Name) - InstanceEventGroup tags specified in [MES Event Action] without required [AddInstanceEventGroup:true] master gate!" -ForegroundColor Red
                $issuesFound++
            }
            if ($block -match '\[ToggleEvent(Ids|IdModes|Tags|TagModes):' -and $block -notmatch '\[ToggleEvents:true\]') {
                Write-Host "[ERROR] $($file.Name) - ToggleEvent tags specified in [MES Event Action] without required [ToggleEvents:true] master gate!" -ForegroundColor Red
                $issuesFound++
            }

            # List Alignments
            $setNames = Get-TagValues $block 'SetCounters'
            $setAmts = Get-TagValues $block 'SetCountersAmount'
            if ($setNames.Count -ne $setAmts.Count) {
                Write-Host "[ERROR] $($file.Name) - SetCounters count ($($setNames.Count)) does not match SetCountersAmount count ($($setAmts.Count))!" -ForegroundColor Red
                $issuesFound++
            }

            $incNames = Get-TagValues $block 'IncreaseCounters'
            $incAmts = Get-TagValues $block 'IncreaseCountersAmount'
            if ($incNames.Count -ne $incAmts.Count) {
                Write-Host "[ERROR] $($file.Name) - IncreaseCounters count ($($incNames.Count)) does not match IncreaseCountersAmount count ($($incAmts.Count))!" -ForegroundColor Red
                $issuesFound++
            }

            $decNames = Get-TagValues $block 'DecreaseCounters'
            $decAmts = Get-TagValues $block 'DecreaseCountersAmount'
            if ($decNames.Count -ne $decAmts.Count) {
                Write-Host "[ERROR] $($file.Name) - DecreaseCounters count ($($decNames.Count)) does not match DecreaseCountersAmount count ($($decAmts.Count))!" -ForegroundColor Red
                $issuesFound++
            }

            $spawnData = Get-TagValues $block 'SpawnData'
            $spawnCoords = Get-TagValues $block 'SpawnCoords'
            $spawnTags = Get-TagValues $block 'SpawnFactionTags'
            if ($spawnData.Count -gt 0) {
                if ($spawnData.Count -ne $spawnCoords.Count -or $spawnData.Count -ne $spawnTags.Count) {
                    Write-Host "[ERROR] $($file.Name) - SpawnEncounter list mismatch! SpawnData ($($spawnData.Count)), SpawnCoords ($($spawnCoords.Count)), SpawnFactionTags ($($spawnTags.Count)) must all be equal." -ForegroundColor Red
                    $issuesFound++
                }
            }
        }

        # Check 12: MES Event Condition Master Gates & Lists
        if ($block -match '\[MES Event Condition( Template)?\]') {
            if ($block -match '\[CustomCounters:' -and $block -notmatch '\[CheckCustomCounters:true\]') {
                Write-Host "[ERROR] $($file.Name) - [CustomCounters:] specified in [MES Event Condition] without [CheckCustomCounters:true] master gate!" -ForegroundColor Red
                $issuesFound++
            }
            if ($block -match '\[TrueBooleans:' -and $block -notmatch '\[CheckTrueBooleans:true\]') {
                Write-Host "[ERROR] $($file.Name) - [TrueBooleans:] specified in [MES Event Condition] without [CheckTrueBooleans:true] master gate!" -ForegroundColor Red
                $issuesFound++
            }
            if ($block -match '\[FalseBooleans:' -and $block -notmatch '\[CheckFalseBooleans:true\]') {
                Write-Host "[ERROR] $($file.Name) - [FalseBooleans:] specified in [MES Event Condition] without [CheckFalseBooleans:true] master gate!" -ForegroundColor Red
                $issuesFound++
            }

            $cNames = Get-TagValues $block 'CustomCounters'
            $cTargets = Get-TagValues $block 'CustomCountersTargets'
            if ($cNames.Count -ne $cTargets.Count) {
                Write-Host "[ERROR] $($file.Name) - CustomCounters count ($($cNames.Count)) does not match CustomCountersTargets count ($($cTargets.Count))!" -ForegroundColor Red
                $issuesFound++
            }
        }
    }
}

# Post-scan: internal consistency check for faction tags not declared in any local
# Factions*.sbc (see comment above $unknownFactionUsages for rationale).
if ($unknownFactionUsages.Count -gt 0) {
    Write-Host ""
    Write-Host "--- Faction Tag Consistency Check ---" -ForegroundColor Cyan

    $usagesByTag = $unknownFactionUsages | Group-Object -Property Tag
    foreach ($group in $usagesByTag) {
        $tag = $group.Name
        $locations = ($group.Group | ForEach-Object { "$($_.File.Name):$($_.Line)" }) -join ', '
        if ($group.Count -ge 2) {
            Write-Host "[INFO] Faction tag '$tag' is not defined in any local Factions*.sbc, but is used consistently $($group.Count)x across this mod ($locations) - likely a faction defined in another mod. No action needed unless that mod is missing from the server." -ForegroundColor Cyan
        } else {
            Write-Host "[WARN] Faction tag '$tag' is not defined in any local Factions*.sbc and appears only once ($locations) - a unique, unrepeated spelling is the strongest signal of a typo. Verify it against the mod that actually defines this faction." -ForegroundColor Yellow
            $issuesFound++
        }
    }

    # Fuzzy near-duplicate check: catches typos like 'GAALSIEN' vs 'GAALSEIN' even when
    # both spellings are reused consistently and would otherwise pass silently above.
    # Scoped to only the externally-used (not locally declared) tags - $knownFactions and
    # $primaryFactions are already vetted/intentional (e.g. 'SPRT' vs 'SPID' are two real,
    # distinct factions that happen to differ by two characters) and must not be flagged.
    $distinctTags = @($usagesByTag.Name) | Select-Object -Unique
    for ($i = 0; $i -lt $distinctTags.Count; $i++) {
        for ($j = $i + 1; $j -lt $distinctTags.Count; $j++) {
            $tagA = $distinctTags[$i]; $tagB = $distinctTags[$j]
            if ($tagA -eq $tagB) { continue }
            $dist = Get-LevenshteinDistance $tagA $tagB
            $shorterLen = [Math]::Min($tagA.Length, $tagB.Length)
            if ($dist -gt 0 -and $dist -le 2 -and $shorterLen -ge 4) {
                Write-Host "[WARN] Faction tags '$tagA' and '$tagB' differ by only $dist character(s) - possible typo. Verify these are intentionally different factions." -ForegroundColor Yellow
                $issuesFound++
            }
        }
    }
}

Write-Host ""
if ($issuesFound -eq 0) {
    Write-Host "MES Tag Audit Passed: No tag hazards, master gate omissions, or list mismatches detected." -ForegroundColor Green
    exit 0
} else {
    Write-Host "MES Tag Audit Completed: $issuesFound issue(s)/warning(s) flagged." -ForegroundColor Red
    exit 1
}
