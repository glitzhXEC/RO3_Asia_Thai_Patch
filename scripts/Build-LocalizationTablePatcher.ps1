param(
    [Parameter(Mandatory = $false)]
    [string]$GameRoot
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($GameRoot)) {
    $GameRoot = Split-Path -Parent $RepoRoot
}

$GameRoot = [System.IO.Path]::GetFullPath($GameRoot)
$Managed = Join-Path $GameRoot 'Client\ro3_Data\Managed'
$Source = Join-Path $RepoRoot 'src\RO3.LocalizationTablePatcher\LocalizationTablePatcherPlugin.cs'
$RecoverySource = Join-Path $RepoRoot 'src\RO3.LocalizationTablePatcher\RecoveryLocalizationPatcher.cs'
$Output = Join-Path $RepoRoot 'Client\BepInEx\plugins\RO3.LocalizationTablePatcher.dll'
$BepInExReference = Join-Path $RepoRoot 'third_party\reference\BepInEx.dll'
$HarmonyReference = Join-Path $GameRoot 'Client\BepInEx\core\0Harmony.dll'
$Csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'

$required = @(
    $Source,
    $RecoverySource,
    $BepInExReference,
    $HarmonyReference,
    (Join-Path $Managed 'UnityEngine.dll'),
    (Join-Path $Managed 'UnityEngine.CoreModule.dll'),
    $Csc
)

foreach ($path in $required) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Localization-table patcher build dependency is missing: $path"
    }
}

New-Item -ItemType Directory -Path (Split-Path -Parent $Output) -Force | Out-Null

$references = @(
    $BepInExReference,
    $HarmonyReference,
    (Join-Path $Managed 'UnityEngine.dll'),
    (Join-Path $Managed 'UnityEngine.CoreModule.dll')
)

$compilerArgs = @('/nologo', '/target:library', '/codepage:65001', "/out:$Output")
$compilerArgs += $references | ForEach-Object { "/reference:$_" }
$compilerArgs += @($Source, $RecoverySource, (Join-Path $RepoRoot 'src\RO3.LocalizationTablePatcher\DisplayTextTranslator.cs'), (Join-Path $RepoRoot 'src\RO3.LocalizationTablePatcher\ChatTranslationPolicy.cs'), (Join-Path $RepoRoot 'src\RO3.LocalizationTablePatcher\ChatTranslationBridge.cs'))

& $Csc @compilerArgs

if ($LASTEXITCODE -ne 0) {
    throw "Localization-table patcher compilation failed with exit code $LASTEXITCODE"
}

Write-Host "[OK] Built: $Output"
