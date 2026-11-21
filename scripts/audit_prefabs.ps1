<#
.SYNOPSIS
    Prefab and Binary Cache Auditor for Space Engineers & MES.
.DESCRIPTION
    Audits .sbc files inside Prefabs directories for common encounter pitfalls:
    1. SubtypeId vs. File Name Mismatch (causes SpawnGroup silent spawn failures).
    2. Stale .sbcB5 binary cache files (causes Keen to load outdated grid definitions).
    3. Remote Control Block Verification (ensures spawned NPC grids can run RivalAI).
    4. Empty or missing SubtypeId definitions.
.PARAMETER Path
    Path to search for prefab .sbc files. Defaults to "Data/Prefabs" or ".".
.PARAMETER CleanStaleB5
    If specified, automatically deletes any .sbcB5 binary cache files found.
.PARAMETER Strict
    If specified, treats warnings (such as SubtypeId vs filename mismatch) as errors.
#>
param(
    [string]$Path = ".",
    [switch]$CleanStaleB5,
    [switch]$Strict
)

# Resolve target directory
$targetDir = $Path
if (-not (Test-Path $targetDir)) {
    Write-Host "[ERROR] Target path does not exist: $targetDir" -ForegroundColor Red
    exit 1
}

# Locate all prefab SBC files
$prefabFiles = Get-ChildItem -Path $targetDir -Filter *.sbc -Recurse | Where-Object {
    $_.FullName -match '\\(Prefabs|StorePrefabs)(\\|$)' -or $_.DirectoryName -match '(Prefabs|StorePrefabs)'
}

# If no files found under specific Prefab folders, check all .sbc files in the provided path
if ($prefabFiles.Count -eq 0) {
    $prefabFiles = Get-ChildItem -Path $targetDir -Filter *.sbc -Recurse
}

# Locate all .sbcB5 binary cache files
$b5Files = Get-ChildItem -Path $targetDir -Filter *.sbcB5 -Recurse

$errorsFound = 0
$warningsFound = 0

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host " Space Engineers Prefab & Binary Cache Auditor" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "Target Directory: $targetDir" -ForegroundColor Gray
Write-Host "Prefabs Found:    $($prefabFiles.Count)" -ForegroundColor Gray
Write-Host "sbcB5 Caches:     $($b5Files.Count)" -ForegroundColor Gray
Write-Host ""

# Check 1: Stale .sbcB5 Binary Caches
if ($b5Files.Count -gt 0) {
    if ($CleanStaleB5) {
        foreach ($b5 in $b5Files) {
            try {
                Remove-Item -Path $b5.FullName -Force
                Write-Host "[CLEANED] Deleted stale binary cache: $($b5.Name)" -ForegroundColor Green
            } catch {
                Write-Host "[ERROR] Failed to delete $($b5.FullName): $_" -ForegroundColor Red
                $errorsFound++
            }
        }
    } else {
        foreach ($b5 in $b5Files) {
            Write-Host "[WARN] Stale binary cache detected: $($b5.Name)" -ForegroundColor Yellow
            Write-Host "       Keen loads .sbcB5 over modified .sbc XML. Run with -CleanStaleB5 to purge." -ForegroundColor DarkGray
            $warningsFound++
        }
    }
}

# Check 2: Prefab SBC Inspections
foreach ($file in $prefabFiles) {
    $raw = [System.IO.File]::ReadAllText($file.FullName)

    # Only process files that define prefabs (contain CubeGrids or PrefabDefinition)
    $isPrefab = ($raw -match '<TypeId>MyObjectBuilder_PrefabDefinition</TypeId>' -or ($raw -match '<Prefab\b' -and $raw -match '<CubeGrids>'))
    if (-not $isPrefab) {
        continue
    }

    $fileNameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
    
    # Prefab Id: SE's own exporter writes the attribute form
    # <Id Type="MyObjectBuilder_PrefabDefinition" Subtype="Name" />; hand-written files
    # often use <Id><TypeId/><SubtypeId/></Id>. Both deserialize to the same SubtypeId.
    $subtypeMatch = [System.Text.RegularExpressions.Regex]::Match($raw, '(?s)<Prefab\b[^>]*>\s*<Id\s[^>]*?Subtype="([^"]*)"')

    if (-not $subtypeMatch.Success) {
        $subtypeMatch = [System.Text.RegularExpressions.Regex]::Match($raw, '(?s)<Prefab\b[^>]*>.*?<Id>.*?<SubtypeId>(.*?)</SubtypeId>')
    }

    if (-not $subtypeMatch.Success) {
        # Fallback: check general SubtypeId
        $subtypeMatch = [System.Text.RegularExpressions.Regex]::Match($raw, '<SubtypeId>(.*?)</SubtypeId>')
    }

    if (-not $subtypeMatch.Success -or [string]::IsNullOrWhiteSpace($subtypeMatch.Groups[1].Value)) {
        Write-Host "[ERROR] $($file.Name) - No valid <SubtypeId> found inside <Prefab> definition!" -ForegroundColor Red
        $errorsFound++
        continue
    }

    $internalSubtype = $subtypeMatch.Groups[1].Value.Trim()

    # Check 2A: SubtypeId vs. File Name Mismatch
    if ($internalSubtype -ne $fileNameWithoutExt) {
        Write-Host "[WARN] $($file.Name) - SubtypeId mismatch!" -ForegroundColor Yellow
        Write-Host "       File Name:   '$fileNameWithoutExt'" -ForegroundColor DarkGray
        Write-Host "       Internal ID: '$internalSubtype'" -ForegroundColor DarkGray
        Write-Host "       SpawnGroups reference '$internalSubtype', NOT the file name. Mismatches cause confusion." -ForegroundColor DarkGray
        $warningsFound++
    }

    # Check 2B: Remote Control Block Check (for RivalAI / Autopilot grids)
    # Search for RemoteControl block definition in the cubegrid blocks
    $hasRemote = ($raw -match 'TypeId>RemoteControl<' -or $raw -match 'TypeId>MyObjectBuilder_RemoteControl<' -or $raw -match 'xsi:type="MyObjectBuilder_RemoteControl"')
    
    if (-not $hasRemote) {
        Write-Host "[INFO] $($file.Name) - No Remote Control block detected." -ForegroundColor Cyan
        Write-Host "       If this grid is intended to run RivalAI behaviors or autopilot, it will spawn inert." -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host "-----------------------------------------------------------------" -ForegroundColor Gray
if ($errorsFound -eq 0 -and ($warningsFound -eq 0 -or -not $Strict)) {
    Write-Host "[PASS] Prefab audit passed ($errorsFound errors, $warningsFound warnings)." -ForegroundColor Green
    exit 0
} else {
    Write-Host "[FAIL] Prefab audit failed ($errorsFound errors, $warningsFound warnings)." -ForegroundColor Red
    exit 1
}
