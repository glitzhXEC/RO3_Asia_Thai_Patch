param(
    [Parameter(Mandatory = $true)][string]$GameClient,
    [switch]$AfterOfficialRepair
)
$ErrorActionPreference = 'Stop'
function Get-Sha256([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '') }
    finally { $stream.Dispose(); $sha.Dispose() }
}
$GameClient = [IO.Path]::GetFullPath($GameClient)
if (-not (Test-Path -LiteralPath (Join-Path $GameClient 'ro3.exe') -PathType Leaf)) {
    throw 'Select the Client folder containing ro3.exe.'
}
$Launcher = Join-Path (Split-Path -Parent $GameClient) 'RO3AsiaLauncher.exe'
if (Get-Process ro3,RO3AsiaLauncher -ErrorAction SilentlyContinue | Where-Object {
    -not $_.Path -or $_.Path -eq (Join-Path $GameClient 'ro3.exe') -or $_.Path -eq $Launcher
}) {
    throw 'Close RO3 and RO3AsiaLauncher, then retry.'
}
# Disable before restoring: the old plugin rewrites these files during Awake.
$Plugin = Join-Path $GameClient 'BepInEx\plugins\RO3.LocalizationTablePatcher.dll'
if (Test-Path -LiteralPath $Plugin) {
    Move-Item -LiteralPath $Plugin -Destination ($Plugin + '.disabled-' + [Guid]::NewGuid().ToString('N'))
}
$Recovery = Join-Path $GameClient 'ro3_Data\StreamingAssets\Recovery'
$State = Join-Path $GameClient 'BepInEx\config\RO3.RecoveryPatchState.txt'
$Targets = @('recovery-compatibility-manifest.json', 'LuaPayload\Localization_en.lua.bytes',
    'LuaPayload\Localization_zh_CN.lua.bytes', 'LuaPayload\Localization_zh_TW.lua.bytes') |
    ForEach-Object { Join-Path $Recovery $_ }
$Backups = @($Targets | ForEach-Object { $_ + '.ro3-ja-original' })
$Count = @($Backups | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }).Count
if ($AfterOfficialRepair) {
    # This is an explicit user assertion that official Repair completed. A local
    # manifest/payload match alone does not establish official authenticity.
    $Current = Get-Sha256 $Targets[0]
    if (Test-Path -LiteralPath $State) {
        foreach ($line in Get-Content -LiteralPath $State) {
            if ($line -match '^PATCHED_MANIFEST_SHA256=([0-9a-fA-F]{64})$' -and $Current -eq $matches[1]) {
                throw 'The known patched manifest is still present. Complete official launcher Repair first.'
            }
        }
    }
    $Manifest = Get-Content -LiteralPath $Targets[0] -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($Target in $Targets[1..3]) {
        $Name = [IO.Path]::GetFileName($Target)
        $Module = @($Manifest.modules | Where-Object { $_.payload_relative_path -ceq $Name })
        if ($Module.Count -ne 1 -or $Module[0].payload_sha256 -notmatch '^[0-9a-fA-F]{64}$' -or
            -not (Test-Path -LiteralPath $Target -PathType Leaf)) {
            throw "Missing or invalid Recovery module: $Name. Complete official launcher Repair first."
        }
        if ((Get-Sha256 $Target) -ne $Module[0].payload_sha256 -or
            (Get-Item -LiteralPath $Target).Length -ne $Module[0].payload_size) {
            throw "Recovery hash/size mismatch: $Name. Complete official launcher Repair first."
        }
    }
    $Remaining = @(@($Backups) + @($State) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
    if ($Remaining.Count -gt 0) {
        # Keep old originals outside Client, including across a later uninstall.
        $Archive = Join-Path (Split-Path -Parent $GameClient) ('RO3-Recovery-Backup-' + [Guid]::NewGuid().ToString('N'))
        foreach ($Path in $Remaining) {
            $Destination = Join-Path $Archive $Path.Substring($GameClient.TrimEnd('\').Length + 1)
            New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null
            Move-Item -LiteralPath $Path -Destination $Destination
        }
        Write-Host "[Recovery] Old backups and state preserved in: $Archive"
    }
    Write-Host '[Recovery] Local manifest/payload consistency checked. Current game files were not overwritten.'
    Write-Host '[Recovery] Run Install-Thai.bat to reinstall the Thai patch.'
    exit 0
}
if ($Count -eq 0 -and -not (Test-Path -LiteralPath $State)) {
    Write-Host '[Recovery] No previous Recovery patch detected. Old patcher disabled if present.'
    exit 0
}
if ($Count -ne 4) {
    foreach ($Backup in $Backups) {
        if (-not (Test-Path -LiteralPath $Backup -PathType Leaf)) { Write-Host "[Recovery] Missing: $Backup" }
    }
    throw "Incomplete original backups ($Count/4). Old patcher disabled; backups preserved. Complete official launcher Repair, then run Recover-After-Official-Repair.bat."
}
$Expected = ''
if (Test-Path -LiteralPath $State) {
    foreach ($line in Get-Content -LiteralPath $State) {
        if ($line -match '^PATCHED_MANIFEST_SHA256=([0-9a-fA-F]{64})$') { $Expected = $matches[1] }
    }
}
$Current = Get-Sha256 $Targets[0]
$Original = Get-Sha256 $Backups[0]
if ($Current -ne $Original -and $Current -ne $Expected) {
    throw 'Unknown manifest version. Old patcher disabled; backups preserved. Complete official launcher Repair, then run Recover-After-Official-Repair.bat.'
}
for ($i = 0; $i -lt $Targets.Count; $i++) {
    Copy-Item -LiteralPath $Backups[$i] -Destination $Targets[$i] -Force
    if ((Get-Sha256 $Targets[$i]) -ne (Get-Sha256 $Backups[$i])) {
        throw "Restore verification failed: $($Targets[$i])"
    }
}
Write-Host '[Recovery] Four files restored and SHA-256 verified. Backups and state preserved.'
Write-Host '[Recovery] Start through RO3AsiaLauncher, not ro3.exe directly.'
