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
    } catch {
        Write-Host "[ERROR] Malformed XML in: $($file.FullName) - $($_.Exception.Message)" -ForegroundColor Red
        $errorsFound++
    }
}

Write-Host ""
if ($errorsFound -eq 0) {
    Write-Host "SBC XML Audit Passed: No deserializer hazards detected." -ForegroundColor Green
    exit 0
} else {
    Write-Host "SBC XML Audit FAILED: $errorsFound error(s) found." -ForegroundColor Red
    exit 1
}
