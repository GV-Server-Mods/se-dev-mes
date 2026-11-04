<#
.SYNOPSIS
    Pre-build XML audit script for Space Engineers SBC files.
.DESCRIPTION
    Audits .sbc files for common Keen deserializer failure modes:
    1. XML comments (<!-- ... -->) inside <Description> tags (crashes ReadElementString with XmlException).
    2. Duplicate SubtypeId elements inside an <Id> block (silently drops subsequent IDs).
    3. Duplicate <Id> elements inside a <Prefab> definition.
    4. Empty or whitespace-only SubtypeId elements.
    5. Malformed XML syntax or missing closing tags.
    6. Empty or whitespace-only files, including prefabs (Keen throws "Root element is missing" and the world fails to load).
    7. MES store-items files (StoreItems\*.xml, read by [MES Store] [FileSource:]). MES loads them with
       XmlSerializer, which fails the whole file on one bad value and silently skips what it does not expect:
       - ERROR: malformed XML, a DOCTYPE, wrong root or an xmlns, no <StoreItems>, a value that does not parse
         (number out of range or with stray characters, wrong-case ItemType or bool, a sign on RequiredMod), a
         comment or child element inside a value, ItemType Gas, a single-value element written twice (only
         the FIRST copy is read), or a list wrapper written twice (only the LAST copy is kept).
       - WARN: an element name MES does not know (names are case-sensitive; ignored), an item with no
         ItemType, several <ItemLimits> (only the first is used), <StoreItemLimits> at all (MES keeps one
         store-limits object for every store), a StoreItemId used twice (generated "<ItemType>/<subtype>" ids
         from <ItemSubtypeIds> included).
    8. A <Definitions> child block written twice (two <EntityComponents>, two <SpawnGroups> ...): Keen's reader
       keeps only the LAST block, so every definition in the earlier ones silently never loads.
.PARAMETER Path
    Path to search for .sbc files. Defaults to current directory.
#>
param(
    [string]$Path = "."
)

$allFiles = Get-ChildItem -Path $Path -Filter *.sbc -Recurse | Where-Object {
    $_.FullName -notmatch '\\(bin|obj)(\\|$)'
}
$files = $allFiles | Where-Object {
    $_.FullName -notmatch '\\(Prefabs|StorePrefabs)(\\|$)'
}

$errorsFound = 0

# Check 6: Empty files. Keen reads every .sbc under Data/ (prefabs too), and an empty one throws
# XmlException "Root element is missing" in MyDefinitionManager.CheckPrefabs. Prefabs are only
# size-checked here: reading them whole is slow and they are exported by the game, not hand-edited.
$emptyFiles = @{}
foreach ($file in $allFiles) {
    $isEmpty = $file.Length -eq 0
    if (-not $isEmpty -and $file.Length -lt 4096) {
        $isEmpty = [string]::IsNullOrWhiteSpace([System.IO.File]::ReadAllText($file.FullName).Trim([char]0xFEFF))
    }
    if ($isEmpty) {
        Write-Host "[ERROR] $($file.FullName) - Empty or whitespace-only .sbc! Keen throws 'Root element is missing' and the world fails to load. Delete the file or restore its content." -ForegroundColor Red
        $errorsFound++
        $emptyFiles[$file.FullName] = $true
    }
}

foreach ($file in $files) {
    if ($emptyFiles.ContainsKey($file.FullName)) { continue }
    $bytes = [System.IO.File]::ReadAllBytes($file.FullName)

    # Check 0: Encoding & BOM integrity (Keen deserializer requires UTF-8)
    $isUtf16 = $false
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        $isUtf16 = $true
    } elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
        $isUtf16 = $true
    }
    if ($isUtf16) {
        Write-Host "[ERROR] $($file.FullName) - UTF-16 encoding detected! Keen's deserializer will fail to read the root element. Re-save as UTF-8 (see Format-MesSbc.ps1)." -ForegroundColor Red
        $errorsFound++
        continue
    }
    # Detect invalid UTF-8 sequences (file saved in a legacy codepage without BOM)
    if ($bytes.Length -gt 0) {
        try {
            $strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true) # throwOnInvalidBytes
            [void]$strictUtf8.GetString($bytes)
        } catch {
            Write-Host "[ERROR] $($file.FullName) - Invalid UTF-8 byte sequence detected (file likely saved in a legacy codepage). Re-save as UTF-8." -ForegroundColor Red
            $errorsFound++
            continue
        }
    }

    $raw = [System.IO.File]::ReadAllText($file.FullName)
    $lines = $raw -split "`r?`n"
    
    # Check 1: XML comments inside <Description>
    $descMatches = [System.Text.RegularExpressions.Regex]::Matches($raw, '(?s)<Description>(.*?)</Description>')
    foreach ($m in $descMatches) {
        if ($m.Groups[1].Value -match '<!--') {
            # Find approximate line number
            $preceding = $raw.Substring(0, $m.Index)
            $lineNo = ($preceding -split "`r?`n").Count
            Write-Host "[ERROR] $($file.Name):$lineNo - Fatal XML comment inside <Description>! Use [//Comment] syntax." -ForegroundColor Red
            $errorsFound++
        }
    }

    # Check 2: Empty or whitespace-only SubtypeId
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '<SubtypeId>\s*</SubtypeId>' -or $lines[$i] -match '<SubtypeId\s*/>') {
            $lineNo = $i + 1
            Write-Host "[ERROR] $($file.Name):$lineNo - Empty <SubtypeId> element detected!" -ForegroundColor Red
            $errorsFound++
        }
    }

    # Check 3: Duplicate IDs using XML DOM
    try {
        [xml]$doc = $raw
        $badChildIds = $doc.SelectNodes("//Id[count(SubtypeId) > 1]")
        if ($badChildIds.Count -gt 0) {
            Write-Host "[ERROR] Duplicate SubtypeId in <Id> in: $($file.FullName)" -ForegroundColor Red
            $errorsFound++
        }
        $badAttrIds = $doc.SelectNodes("//*[count(Id) > 1]")
        if ($badAttrIds.Count -gt 0) {
            Write-Host "[ERROR] Duplicate <Id> tag in: $($file.FullName)" -ForegroundColor Red
            $errorsFound++
        }
        # Check 8: a repeated <Definitions> block (MyObjectBuilder_Definitions). Its array wrappers
        # (<CubeBlocks>, <EntityComponents> ...) are replaced by each later copy, so only the last loads;
        # the single values keep the first copy; the flat <Definition> and <Environment> lists append.
        $defRoot = $doc.DocumentElement
        if ($defRoot -and $defRoot.LocalName -ceq 'Definitions') {
            $dupBlocks = @($defRoot.ChildNodes | Where-Object { $_.NodeType -eq 'Element' } |
                Group-Object -CaseSensitive -Property LocalName |
                Where-Object { $_.Count -gt 1 -and $_.Name -cnotin 'Definition', 'Environment' })
            foreach ($g in $dupBlocks) {
                $kept = if ($g.Name -cin 'Configuration', 'ShipSoundSystem') { 'FIRST' } else { 'LAST' }
                Write-Host "[ERROR] $($file.Name): <Definitions> has $($g.Count) <$($g.Name)> blocks. Only the $kept one loads; the definitions in the others are silently dropped. Merge them into one <$($g.Name)>." -ForegroundColor Red
                $errorsFound++
            }
        }
    } catch {
        Write-Host "[ERROR] Malformed XML in: $($file.FullName) - $($_.Exception.Message)" -ForegroundColor Red
        $errorsFound++
    }
}

# Check 7: MES store-items files. Layout mirrors MES Files/StoreItems.cs; MES reads the file with
# MyAPIGateway.Utilities.SerializeFromXML (a plain XmlSerializer over XmlReader.Create): one exception drops the
# whole file (logged only with the Error debug flag on). Element names are case-sensitive and namespace-free.
# A repeated single-value element keeps its FIRST copy (later copies are skipped unread); a repeated array
# wrapper (<StoreItems>, <StoreItemLimits>, <ItemSubtypeIds>) is read every time and the LAST copy replaces the
# others; the <StoreItemsList> list appends.
$warningsFound = 0
$xmlWs = [char[]]@(' ', "`t", "`r", "`n")  # the only whitespace XmlConvert trims

function New-FieldMap([hashtable]$h) {
    $d = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal)
    foreach ($k in $h.Keys) { $d[$k] = $h[$k] }
    return , $d
}
$containerFields = New-FieldMap @{ StoreItems = 'array'; StoreItemLimits = 'array'; StoreItemsList = 'list' }
$storeValues = New-FieldMap @{ CustomPrice = 'long'; MinPriceMultiplier = 'short'; MaxPriceMultiplier = 'short'
    MinAmount = 'int'; MaxAmount = 'int'; SandboxCounterMultiplier = 'string' }
$storeItemFields = New-FieldMap @{ StoreItemId = 'string'; ItemType = 'enum'; ItemSubtypeId = 'string'
    RequiredMod = 'ulong'; PCU = 'int'; IsCustomItem = 'bool'; ItemSubtypeIds = 'array'; Offer = 'values'; Order = 'values' }
$limitTable = @{}
foreach ($kind in 'Ore', 'Ingot', 'Component', 'Tool', 'Consumable', 'Gas', 'Ammo', 'Seed') {
    $limitTable["Max${kind}Amount"] = 'int'; $limitTable["Max${kind}Value"] = 'int'
}
$storeLimitFields = New-FieldMap $limitTable
$storeItemTypes = 'None', 'Ore', 'Ingot', 'Component', 'Ammo', 'Tool', 'Consumable', 'RandomCraftable',
    'RandomItem', 'Oxygen', 'Hydrogen', 'Prefab', 'Seed', 'Item', 'Datapad', 'OxygenContainer', 'GasContainer', 'Gas'
$intRanges = @{ short = @(-32768, 32767); int = @(-2147483648, 2147483647)
    long = @([long]::MinValue, [long]::MaxValue); ulong = @(0, [decimal][System.UInt64]::MaxValue) }

function Test-StoreValue([string]$type, [string]$text) {
    # True when XmlSerializer (XmlConvert) would parse $text as $type.
    if ($type -eq 'string') { return $true }
    if ($type -eq 'enum') { return $storeItemTypes -ccontains $text }  # exact: ' Hydrogen ' and 'hydrogen' throw
    $t = $text.Trim($xmlWs)
    if ($type -eq 'bool') { return $t -cin 'true', 'false', '1', '0' }
    $pattern = if ($type -eq 'ulong') { '^[0-9]+$' } else { '^[+-]?[0-9]+$' }  # ulong takes no sign at all
    if ($t -cnotmatch $pattern) { return $false }
    try {
        $n = [decimal]::Parse($t, [Globalization.NumberStyles]::AllowLeadingSign, [Globalization.CultureInfo]::InvariantCulture)
    } catch { return $false }
    return $n -ge $intRanges[$type][0] -and $n -le $intRanges[$type][1]
}

function Get-ElementKey($el) {
    if ($el.NamespaceURI) { return '{' + $el.NamespaceURI + '}' + $el.LocalName }
    return $el.LocalName
}

function Test-StoreElement($node, $fields, [string]$where, [string]$fileName) {
    # Children of one object: unknown names (WARN), repeats (ERROR), leaf content and values (ERROR).
    $groups = @($node.ChildNodes | Where-Object { $_.NodeType -eq 'Element' } |
        Group-Object -CaseSensitive -Property { Get-ElementKey $_ })
    foreach ($g in $groups) {
        $type = $null
        if (-not $fields.TryGetValue($g.Name, [ref]$type)) {
            Write-Host "[WARN] ${fileName}: $where <$($g.Name)> is not a field MES reads here (names are case-sensitive); it is ignored." -ForegroundColor Yellow
            $script:warningsFound++
            continue
        }
        $els = @($g.Group)
        if ($els.Count -gt 1 -and $type -ne 'list') {
            $vals = if ($type -in 'array', 'values') { '' } else { ' (' + (($els | ForEach-Object { $_.InnerText.Trim() }) -join ', ') + ')' }
            if ($type -eq 'array') {
                Write-Host "[ERROR] ${fileName}: $where <$($g.Name)> appears $($els.Count) times. XmlSerializer keeps only the LAST copy; the entries in the others are lost. Merge them into one <$($g.Name)>." -ForegroundColor Red
            } else {
                Write-Host "[ERROR] ${fileName}: $where <$($g.Name)> appears $($els.Count) times$vals. XmlSerializer reads only the FIRST copy and skips the others with no log; delete them." -ForegroundColor Red
                $els = @($els[0])  # later copies are never parsed, so their values cannot break the file
            }
            $script:errorsFound++
        }
        if ($type -in 'array', 'list', 'values') { continue }
        foreach ($el in $els) {
            $inner = @($el.ChildNodes | Where-Object { $_.NodeType -in 'Element', 'Comment', 'ProcessingInstruction' })
            if ($inner.Count -gt 0) {
                Write-Host "[ERROR] ${fileName}: $where <$($g.Name)> contains a comment or child element. XmlSerializer throws and MES skips the WHOLE file; move the comment outside the element." -ForegroundColor Red
                $script:errorsFound++
            } elseif (-not (Test-StoreValue $type $el.InnerText)) {
                Write-Host "[ERROR] ${fileName}: $where <$($g.Name)>$($el.InnerText)</$($g.Name)> is not a valid $type. XmlSerializer throws and MES skips the WHOLE file." -ForegroundColor Red
                $script:errorsFound++
            }
        }
    }
}

function Get-Children($node, [string]$name) {
    # Namespace-free child elements with this exact name (what XmlSerializer matches).
    if (-not $node) { return @() }
    return @($node.ChildNodes | Where-Object { $_.NodeType -eq 'Element' -and $_.LocalName -ceq $name -and -not $_.NamespaceURI })
}

function Test-IsNil($el) {
    $nil = $el.GetAttribute('nil', 'http://www.w3.org/2001/XMLSchema-instance')
    return $nil.Trim($xmlWs) -cin 'true', '1'
}

$storeFiles = Get-ChildItem -Path $Path -Filter *.xml -Recurse | Where-Object {
    $_.Directory.Name -eq 'StoreItems' -and $_.FullName -notmatch '\\(bin|obj)(\\|$)'
}
foreach ($file in $storeFiles) {
    $name = $file.Name
    try {
        $doc = New-Object System.Xml.XmlDocument
        $doc.XmlResolver = $null
        $doc.LoadXml([System.IO.File]::ReadAllText($file.FullName))
    } catch {
        Write-Host "[ERROR] Malformed XML in store-items file: $($file.FullName) - $($_.Exception.Message)" -ForegroundColor Red
        $errorsFound++
        continue
    }
    if ($doc.DocumentType) {
        Write-Host "[ERROR] ${name}: has a <!DOCTYPE>. MES's XmlReader prohibits DTDs, so it throws and MES skips the file. Delete the DOCTYPE line." -ForegroundColor Red
        $errorsFound++
        continue
    }
    $root = $doc.DocumentElement
    if ($root.LocalName -cne 'StoreItemsContainer' -or $root.NamespaceURI) {
        Write-Host "[ERROR] ${name}: root is <$(Get-ElementKey $root)>, MES expects <StoreItemsContainer> with no xmlns. XmlSerializer throws and MES skips the file." -ForegroundColor Red
        $errorsFound++
        continue
    }
    Test-StoreElement $root $containerFields '<StoreItemsContainer>' $name
    $wrappers = @(Get-Children $root 'StoreItems')
    $lists = @(Get-Children $root 'StoreItemsList')
    $live = $null
    if ($wrappers.Count -gt 0) { $live = $wrappers[-1] }
    if (-not $live -or (Test-IsNil $live)) {
        Write-Host "[ERROR] ${name}: no <StoreItems> list (or xsi:nil). StoreProfile.Setup reads StoreItems.Length and throws for every [MES Store] profile using this file (read in code, not tested in game: it may stop the world loading)." -ForegroundColor Red
        $errorsFound++
    }
    $ids = New-Object 'System.Collections.Generic.Dictionary[string,int]' ([StringComparer]::Ordinal)
    foreach ($w in @($wrappers) + @($lists)) {
        # Every wrapper is parsed (a bad value anywhere drops the file), but only the last <StoreItems> and the
        # <StoreItemsList> entries reach the store.
        $loads = [object]::ReferenceEquals($w, $live) -or $lists -contains $w
        foreach ($item in @($w.ChildNodes | Where-Object { $_.NodeType -eq 'Element' })) {
            if ($item.LocalName -cne 'StoreItem' -or $item.NamespaceURI) {
                Write-Host "[WARN] ${name}: <$($w.LocalName)> holds <$(Get-ElementKey $item)>; only <StoreItem> is read." -ForegroundColor Yellow
                $warningsFound++
                continue
            }
            $idEl = @(Get-Children $item 'StoreItemId')[0]
            $label = if ($idEl) { "StoreItem '$($idEl.InnerText)'" } else { 'StoreItem (no StoreItemId)' }
            Test-StoreElement $item $storeItemFields $label $name
            foreach ($side in 'Offer', 'Order') {
                $v = @(Get-Children $item $side)[0]
                if ($v) { Test-StoreElement $v $storeValues "$label > $side" $name }
            }
            $subWrappers = @(Get-Children $item 'ItemSubtypeIds')
            foreach ($sw in $subWrappers) {
                foreach ($sub in @($sw.ChildNodes | Where-Object { $_.NodeType -eq 'Element' })) {
                    if ($sub.LocalName -cne 'ItemSubtypeId' -or $sub.NamespaceURI) {
                        Write-Host "[WARN] ${name}: $label <ItemSubtypeIds> holds <$(Get-ElementKey $sub)>; only <ItemSubtypeId> is read." -ForegroundColor Yellow
                        $warningsFound++
                    } elseif (@($sub.ChildNodes | Where-Object { $_.NodeType -in 'Element', 'Comment', 'ProcessingInstruction' }).Count -gt 0) {
                        Write-Host "[ERROR] ${name}: $label <ItemSubtypeId> contains a comment or child element. XmlSerializer throws and MES skips the WHOLE file." -ForegroundColor Red
                        $errorsFound++
                    }
                }
            }
            if (-not $loads) { continue }
            $typeEl = @(Get-Children $item 'ItemType')[0]
            $itemType = if ($typeEl) { $typeEl.InnerText } else { 'None' }
            if (-not $typeEl) {
                Write-Host "[WARN] ${name}: $label has no <ItemType> (None). MES skips it when stocking a store." -ForegroundColor Yellow
                $warningsFound++
            } elseif ($itemType -ceq 'Gas') {
                Write-Host "[ERROR] ${name}: $label has ItemType Gas. StoreProfile.CreateStoreItem returns null for Gas and AddItemToStore throws, so the ApplyStoreProfiles action stops part-way (the rest of that store and the rest of the action are skipped; log: Error while executing action: 'ApplyStoreProfiles'). Use Hydrogen or Oxygen." -ForegroundColor Red
                $errorsFound++
            }
            # ProfileManager adds one entry per <ItemSubtypeId>, with the StoreItemId "<ItemType>/<subtype>".
            $itemIds = @()
            if ($idEl -and $idEl.InnerText) { $itemIds += $idEl.InnerText }
            if ($subWrappers.Count -gt 0) {
                foreach ($sub in @(Get-Children $subWrappers[-1] 'ItemSubtypeId')) { $itemIds += "$itemType/$($sub.InnerText)" }
            }
            foreach ($key in $itemIds) {
                $count = 0
                [void]$ids.TryGetValue($key, [ref]$count)
                $ids[$key] = $count + 1
            }
        }
    }
    foreach ($kv in $ids.GetEnumerator()) {
        if ($kv.Value -gt 1) {
            Write-Host "[WARN] ${name}: StoreItemId '$($kv.Key)' is used by $($kv.Value) entries. A store that names it can stock all of them: its draw chance multiplies, items merge into one listing with the amounts added, and a prefab is listed twice." -ForegroundColor Yellow
            $warningsFound++
        }
    }
    $limitWrappers = @(Get-Children $root 'StoreItemLimits')
    foreach ($lw in $limitWrappers) {
        foreach ($l in @($lw.ChildNodes | Where-Object { $_.NodeType -eq 'Element' })) {
            if ($l.LocalName -cne 'ItemLimits' -or $l.NamespaceURI) {
                Write-Host "[WARN] ${name}: <StoreItemLimits> holds <$(Get-ElementKey $l)>; only <ItemLimits> is read." -ForegroundColor Yellow
                $warningsFound++
                continue
            }
            Test-StoreElement $l $storeLimitFields '<ItemLimits>' $name
        }
    }
    if ($limitWrappers.Count -gt 0) {
        $limits = @(Get-Children $limitWrappers[-1] 'ItemLimits')
        if ($limits.Count -gt 1) {
            Write-Host "[WARN] ${name}: $($limits.Count) <ItemLimits> entries; MES uses only the first." -ForegroundColor Yellow
            $warningsFound++
        }
        Write-Host "[WARN] ${name}: has <StoreItemLimits>. MES keeps ONE limits object (static StoreProfile._storeLimits) for every [MES Store] profile, so the last-loaded file's limits apply to all MES stores." -ForegroundColor Yellow
        $warningsFound++
    }
}

Write-Host ""
if ($errorsFound -eq 0) {
    Write-Host "SBC XML Audit Passed: No deserializer hazards detected ($warningsFound warning(s))." -ForegroundColor Green
    exit 0
} else {
    Write-Host "SBC XML Audit FAILED: $errorsFound error(s) found ($warningsFound warning(s))." -ForegroundColor Red
    exit 1
}
