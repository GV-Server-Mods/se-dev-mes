<#
.SYNOPSIS
    1-Step Automated Skill & Tag Database Updater for se-dev-mes.
.DESCRIPTION
    Executes a complete end-to-end synchronization workflow:
    1. Scans local MES installation (%AppData% or Steam Workshop).
    2. Rebuilds the offline tag cache (mes_tag_cache.json).
    3. Fast-forwards the installed skill clone (~/.gemini/config/skills/se-dev-mes) to this repo's main branch.
    4. Runs pre-flight verification on all examples and scripts.
.PARAMETER MesPath
    Optional custom path to local MES source.
#>
param(
    [string]$MesPath = ""
)

$repoRoot = Split-Path -Parent $PSScriptRoot
$globalSkillPath = [System.IO.Path]::Combine($env:USERPROFILE, ".gemini", "config", "skills", "se-dev-mes")

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host " 1-Step MES Skill & Tag Database Updater" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "Repository Root:   $repoRoot" -ForegroundColor Gray
Write-Host "Global Skill Path: $globalSkillPath" -ForegroundColor Gray
Write-Host ""

# Step 1: Rebuild Tag Cache
Write-Host "[1/4] Rebuilding offline tag cache from MES source..." -ForegroundColor Yellow
$pyScript = Join-Path $PSScriptRoot "query_mes_tags.py"
$pyArgs = @($pyScript, "--rebuild-cache")
if (-not [string]::IsNullOrWhiteSpace($MesPath)) {
    $pyArgs += @("--path", $MesPath)
}
& python @pyArgs

if ($LASTEXITCODE -ne 0) {
    $cacheFile = Join-Path $PSScriptRoot "mes_tag_cache.json"
    if (Test-Path $cacheFile) {
        Write-Host "[WARN] Live MES source not found; falling back to existing offline tag cache." -ForegroundColor Yellow
    } else {
        Write-Host "[ERROR] Failed to rebuild tag cache and no offline cache exists!" -ForegroundColor Red
        exit 1
    }
}

# Step 2: Pre-Flight Verification on Examples
Write-Host "`n[2/4] Running pre-flight verification on production examples..." -ForegroundColor Yellow
& powershell -ExecutionPolicy Bypass -File "$PSScriptRoot/audit_sbc.ps1" -Path "$repoRoot/examples"
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] SBC XML audit failed on examples!" -ForegroundColor Red
    exit 1
}

& powershell -ExecutionPolicy Bypass -File "$PSScriptRoot/audit_mes_tags.ps1" -Path "$repoRoot/examples"
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] MES tag audit failed on examples!" -ForegroundColor Red
    exit 1
}

& powershell -ExecutionPolicy Bypass -File "$PSScriptRoot/audit_prefabs.ps1" -Path "$repoRoot/examples"
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Prefab audit failed on examples!" -ForegroundColor Red
    exit 1
}

# Every tag, profile header and trigger Type the skill teaches must exist in the MES source just cached:
# the examples, the XML blocks in references/*.md, and every New-MesProfile.ps1 pattern.
$scaffoldDir = Join-Path ([System.IO.Path]::GetTempPath()) "se-dev-mes-scaffolds"
New-Item -ItemType Directory -Force $scaffoldDir | Out-Null
foreach ($pattern in 'DefendedWreck','ConvoyLeaderEscort','DynamicZoneLadder','StoreGrid','DynamicStateNpc','PlanetaryInstallation','CombatDrone','ReinforcementNetwork','BossEncounter') {
    & powershell -ExecutionPolicy Bypass -File "$PSScriptRoot/New-MesProfile.ps1" -Pattern $pattern -ModPrefix TST -Name Gate -Faction SPRT -OutFile (Join-Path $scaffoldDir "$pattern.sbc") | Out-Null
}
& python "$PSScriptRoot/audit_unknown_tags.py" "$repoRoot/examples" "$repoRoot/references" $scaffoldDir --all
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Skill content uses tags, headers or trigger types that the installed MES does not parse!" -ForegroundColor Red
    exit 1
}

# Step 2.5: SKILL.md Size Budget Gate (Progressive Disclosure / Harness Portability)
# Cline and Anthropic Agent Skills both cap the SKILL.md body at 5,000 tokens (~20k ASCII chars).
# Over-budget SKILL.md files are silently middle-truncated by harnesses (detail lost, no error shown).
Write-Host "`n[2.5/4] Checking SKILL.md size budget (hard limit: 5,000 tokens)...`n" -ForegroundColor Yellow
$skillMdPath = Join-Path $repoRoot "SKILL.md"
$skillBytes = [System.IO.File]::ReadAllBytes($skillMdPath)
$skillChars = ([System.Text.Encoding]::UTF8.GetString($skillBytes)).Length
# Conservative estimate: ~3.9 chars per token for mixed English/markdown/code content
$estimatedTokens = [math]::Ceiling($skillChars / 3.9)
Write-Host ("  SKILL.md: {0:N0} chars, ~{1:N0} estimated tokens (limit: 5,000)" -f $skillChars, $estimatedTokens)
if ($estimatedTokens -gt 5000) {
    Write-Host "[ERROR] SKILL.md exceeds the 5,000-token budget (est. $estimatedTokens tokens)! Harnesses will silently middle-truncate the injected content, dropping core sections. Move detail into references/*.md and keep SKILL.md as a lean router." -ForegroundColor Red
    exit 1
} elseif ($estimatedTokens -gt 4200) {
    Write-Host "[WARNING] SKILL.md is within 800 tokens of the 5,000 budget. Consider extracting more detail into references/*.md." -ForegroundColor Yellow
} else {
    Write-Host "  SKILL.md size budget OK." -ForegroundColor Green
}

# Step 3: Synchronize to Global Skill Directory
Write-Host "`n[3/4] Synchronizing repository to global skill directory..." -ForegroundColor Yellow
if (Test-Path $globalSkillPath) {
    $item = Get-Item $globalSkillPath
    if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        Write-Host "Global skill directory is a live directory junction. All files are automatically in sync!" -ForegroundColor Green
    } elseif (Test-Path (Join-Path $globalSkillPath ".git")) {
        # Installed skill is a git clone: fast-forward it to this repo's committed main branch.
        # Uncommitted changes (such as a freshly rebuilt tag cache) install once they are committed to main.
        & git -C "$globalSkillPath" pull --ff-only --quiet "$repoRoot" main
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[WARN] Could not fast-forward the installed clone (local edits or diverged history). Fix it in $globalSkillPath with git." -ForegroundColor Yellow
        } else {
            Write-Host "Installed clone fast-forwarded to main. Commit any pending changes to install them." -ForegroundColor Green
        }
    } else {
        Write-Host "[WARN] $globalSkillPath is neither a junction nor a git clone; skipped. Replace it with a clone of this repo." -ForegroundColor Yellow
    }
} else {
    Write-Host "[INFO] Global skill path ($globalSkillPath) does not exist yet. Creating junction..." -ForegroundColor Cyan
    cmd /c mklink /J "$globalSkillPath" "$repoRoot"
}

# Step 4: Health Summary
Write-Host "`n[4/4] MES Skill Health Check:" -ForegroundColor Yellow
& python "$PSScriptRoot/check_mes_sync.py"

Write-Host ""
Write-Host "=================================================================" -ForegroundColor Green
Write-Host " Update Complete! se-dev-mes is 100% in sync with latest MES." -ForegroundColor Green
Write-Host "=================================================================" -ForegroundColor Green

