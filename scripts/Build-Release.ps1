param(
    [Parameter(Mandatory = $false)]
    [string]$Version = (Get-Date -Format 'yyyy.MM.dd'),

    [Parameter(Mandatory = $false)]
    [string]$GameRoot
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot

function Assert-PackagingBatchFile([string]$Path) {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        throw "Packaging BAT must not contain a UTF-8 BOM: $Path"
    }
    $text = [System.Text.Encoding]::ASCII.GetString($bytes)
    if ($text -notmatch 'echo "%TARGET%"') {
        throw "Packaging BAT does not quote TARGET path output: $Path"
    }
}

if ([string]::IsNullOrWhiteSpace($GameRoot)) {
    $GameRoot = Split-Path -Parent $RepoRoot
}
$GameRoot = [System.IO.Path]::GetFullPath($GameRoot)
$GameClient = Join-Path $GameRoot 'Client'
if (-not (Test-Path -LiteralPath (Join-Path $GameClient 'ro3.exe') -PathType Leaf)) {
    throw "ro3.exe was not found under: $GameClient"
}

# Regenerate and validate all tracked translation outputs before packaging.
Push-Location $RepoRoot
try {
    & py -3 '_TranslationWorkspace\import_translations.py' --check
    if ($LASTEXITCODE -ne 0) { throw "Translation validation failed with exit code $LASTEXITCODE" }
    & py -3 '_TranslationWorkspace\import_translations.py'
    if ($LASTEXITCODE -ne 0) { throw "Translation generation failed with exit code $LASTEXITCODE" }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'scripts\Build-LocalizationTablePatcher.ps1' -GameRoot $GameRoot
    if ($LASTEXITCODE -ne 0) { throw "Localization-table patcher build failed with exit code $LASTEXITCODE" }
}
finally {
    Pop-Location
}

$SafeVersion = $Version -replace '[^0-9A-Za-z._-]', '_'
$DistRoot = Join-Path $RepoRoot 'dist'
$StageName = "RO3_Asia_Thai_Patch_$SafeVersion"
$Stage = Join-Path $DistRoot $StageName
$Zip = Join-Path $DistRoot ($StageName + '.zip')

New-Item -ItemType Directory -Path $DistRoot -Force | Out-Null
if (Test-Path -LiteralPath $Stage) { Remove-Item -LiteralPath $Stage -Recurse -Force }
if (Test-Path -LiteralPath $Zip) { Remove-Item -LiteralPath $Zip -Force }
New-Item -ItemType Directory -Path (Join-Path $Stage 'payload') -Force | Out-Null

Copy-Item -LiteralPath (Join-Path $RepoRoot 'packaging\Install-Thai.bat') -Destination $Stage
Copy-Item -LiteralPath (Join-Path $RepoRoot 'packaging\Update-Thai.bat') -Destination $Stage
Copy-Item -LiteralPath (Join-Path $RepoRoot 'packaging\Update-Latest.ps1') -Destination $Stage
Copy-Item -LiteralPath (Join-Path $RepoRoot 'packaging\Uninstall-Thai.bat') -Destination $Stage
Copy-Item -LiteralPath (Join-Path $RepoRoot 'packaging\Restore-Recovery.ps1') -Destination $Stage
Copy-Item -LiteralPath (Join-Path $RepoRoot 'packaging\Recover-Thai.bat') -Destination $Stage
Copy-Item -LiteralPath (Join-Path $RepoRoot 'packaging\Recover-After-Official-Repair.bat') -Destination $Stage
Copy-Item -LiteralPath (Join-Path $RepoRoot 'packaging\README.txt') -Destination $Stage
Assert-PackagingBatchFile (Join-Path $Stage 'Install-Thai.bat')
Assert-PackagingBatchFile (Join-Path $Stage 'Uninstall-Thai.bat')
Copy-Item -LiteralPath (Join-Path $RepoRoot 'THIRD_PARTY_NOTICES.md') -Destination $Stage
New-Item -ItemType Directory -Path (Join-Path $Stage 'licenses') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $RepoRoot 'third_party\BepInEx-LICENSE.txt') -Destination (Join-Path $Stage 'licenses\BepInEx-LICENSE.txt')
Copy-Item -LiteralPath (Join-Path $RepoRoot 'third_party\XUnity-AutoTranslator-LICENSE.txt') -Destination (Join-Path $Stage 'licenses\XUnity-AutoTranslator-LICENSE.txt')
Set-Content -LiteralPath (Join-Path $Stage 'VERSION.txt') -Value $Version -Encoding ASCII

# Include the offline hand-translation editor for contributors.
Copy-Item -LiteralPath (Join-Path $RepoRoot 'Translation-Editor') `
    -Destination (Join-Path $Stage 'Translation-Editor') -Recurse -Force

$runtimeFiles = @(
    '.doorstop_version',
    'doorstop_config.ini',
    'winhttp.dll',
    'BepInEx\config\BepInEx.cfg',
    'BepInEx\config\gravydevsupreme.xunity.resourceredirector.cfg',
    'BepInEx\core\0Harmony.dll',
    'BepInEx\core\0Harmony20.dll',
    'BepInEx\core\BepInEx.dll',
    'BepInEx\core\BepInEx.Harmony.dll',
    'BepInEx\core\BepInEx.Preloader.dll',
    'BepInEx\core\HarmonyXInterop.dll',
    'BepInEx\core\Mono.Cecil.dll',
    'BepInEx\core\Mono.Cecil.Mdb.dll',
    'BepInEx\core\Mono.Cecil.Pdb.dll',
    'BepInEx\core\Mono.Cecil.Rocks.dll',
    'BepInEx\core\MonoMod.RuntimeDetour.dll',
    'BepInEx\core\MonoMod.Utils.dll',
    'BepInEx\core\XUnity.Common.dll',
    'BepInEx\plugins\XUnity.AutoTranslator\ExIni.dll',
    'BepInEx\plugins\XUnity.AutoTranslator\XUnity.AutoTranslator.Plugin.BepInEx.dll',
    'BepInEx\plugins\XUnity.AutoTranslator\XUnity.AutoTranslator.Plugin.Core.dll',
    'BepInEx\plugins\XUnity.AutoTranslator\XUnity.AutoTranslator.Plugin.ExtProtocol.dll',
    'BepInEx\plugins\XUnity.ResourceRedirector\XUnity.ResourceRedirector.BepInEx.dll',
    'BepInEx\plugins\XUnity.ResourceRedirector\XUnity.ResourceRedirector.dll'
)

foreach ($relative in $runtimeFiles) {
    $source = Join-Path $GameClient $relative
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Required runtime file is missing: $source"
    }
    $destination = Join-Path (Join-Path $Stage 'payload') $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Force
}

$repoPayloadFiles = @(
    'arialuni_sdf_u2022',
    'BepInEx\config\AutoTranslatorConfig.ini',
    'BepInEx\config\RO3.LocalizationOverrides.tsv',
    'BepInEx\config\RO3.LocalizationAliases.tsv',
    'BepInEx\plugins\RO3.LocalizationTablePatcher.dll',
    'BepInEx\Translation\ja\Text\_AutoGeneratedTranslations.txt',
    'BepInEx\Translation\ja\Text\RO3_CanonicalTranslations.txt',
    'BepInEx\Translation\ja\Text\RO3_PriorityOverrides.txt',
    'BepInEx\Translation\ja\Text\RO3_RuntimePlaceholders.txt'
)
foreach ($relative in $repoPayloadFiles) {
    $source = Join-Path (Join-Path $RepoRoot 'Client') $relative
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Repository payload file is missing: $source"
    }
    $destination = Join-Path (Join-Path $Stage 'payload') $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Force
}

# Development-only diagnostics/deprecated implementations must never leak into
# an install release.
$forbiddenPayloadFiles = @(
    'BepInEx\plugins\RO3WorldNameplateProbe.dll',
    'BepInEx\plugins\RO3.LuaNameplateModuleInspector.dll',
    'BepInEx\plugins\RO3.WorldNameTranslator.dll',
    'BepInEx\config\RO3.WorldNameTranslations.tsv'
)
foreach ($relative in $forbiddenPayloadFiles) {
    $path = Join-Path (Join-Path $Stage 'payload') $relative
    if (Test-Path -LiteralPath $path) {
        throw "Forbidden diagnostic/deprecated file unexpectedly present in release payload: $path"
    }
}

Compress-Archive -LiteralPath $Stage -DestinationPath $Zip -CompressionLevel Optimal
$Hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Zip).Hash
Write-Host ""
Write-Host "[OK] Release package created"
Write-Host "     Version: $Version"
Write-Host "     ZIP:     $Zip"
Write-Host "     SHA256:  $Hash"
