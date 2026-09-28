param(
    [Parameter(Mandatory = $false)]
    [string]$GameTarget,

    [Parameter(Mandatory = $false)]
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Repository = 'glitzhXEC/RO3_Asia_Thai_Patch'
$LatestReleaseApi = "https://api.github.com/repos/$Repository/releases/latest"
$AssetPattern = '^RO3_Asia_Thai_Patch_.+\.zip$'
$InstallMarker = '.ro3-thai-patch-install.txt'

function Normalize-Version([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    return $Value.Trim().TrimStart('v', 'V')
}

function Resolve-GameClient([string]$Candidate) {
    if ([string]::IsNullOrWhiteSpace($Candidate)) {
        if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'ro3.exe') -PathType Leaf) {
            $Candidate = $PSScriptRoot
        }
        else {
            Write-Host ''
            Write-Host 'Enter the RO3 Client folder that contains ro3.exe.'
            Write-Host 'You can also close this window and drag ro3.exe or its folder onto Update-Thai.bat.'
            Write-Host ''
            $Candidate = Read-Host '>'
        }
    }

    $Candidate = $Candidate.Trim().Trim('"')
    if ([string]::IsNullOrWhiteSpace($Candidate)) {
        throw 'No RO3 Client folder was specified.'
    }

    $Full = [System.IO.Path]::GetFullPath($Candidate)
    if ((Test-Path -LiteralPath $Full -PathType Leaf) -and
        [string]::Equals(
            [System.IO.Path]::GetFileName($Full),
            'ro3.exe',
            [System.StringComparison]::OrdinalIgnoreCase)) {
        $Full = Split-Path -Parent $Full
    }

    $Exe = Join-Path $Full 'ro3.exe'
    if (-not (Test-Path -LiteralPath $Exe -PathType Leaf)) {
        throw "ro3.exe was not found in: $Full"
    }
    return $Full
}

function Get-InstalledVersion([string]$GameClient) {
    $Marker = Join-Path $GameClient $InstallMarker
    if (-not (Test-Path -LiteralPath $Marker -PathType Leaf)) { return '' }
    foreach ($Line in Get-Content -LiteralPath $Marker) {
        if ($Line -match '^PATCH_VERSION=(.*)$') {
            return (Normalize-Version $matches[1])
        }
    }
    return ''
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

$GameClient = Resolve-GameClient $GameTarget
$InstalledVersion = Get-InstalledVersion $GameClient

try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}
catch {
}

$Headers = @{
    'User-Agent' = 'RO3-Asia-Thai-Patch-Updater'
    'Accept' = 'application/vnd.github+json'
}

Write-Host ''
Write-Host "Checking latest GitHub release: $Repository"
$Release = Invoke-RestMethod -Uri $LatestReleaseApi -Headers $Headers -Method Get
if ($null -eq $Release -or [string]::IsNullOrWhiteSpace([string]$Release.tag_name)) {
    throw 'GitHub did not return a valid latest release.'
}

$LatestVersion = Normalize-Version ([string]$Release.tag_name)
$Assets = @($Release.assets | Where-Object { [string]$_.name -match $AssetPattern })
if ($Assets.Count -ne 1) {
    $Names = @($Release.assets | ForEach-Object { [string]$_.name }) -join ', '
    throw "Expected exactly one RO3 release ZIP asset, found $($Assets.Count). Assets: $Names"
}
$Asset = $Assets[0]

Write-Host "Installed version: " -NoNewline
Write-Host $(if ($InstalledVersion) { $InstalledVersion } else { '<unknown/not installed by this package>' })
Write-Host "Latest version:    $LatestVersion"
Write-Host "Latest ZIP:        $($Asset.name)"

if ($CheckOnly) {
    if ($InstalledVersion -and $InstalledVersion -eq $LatestVersion) {
        Write-Host '[OK] The installed Thai patch is already the latest release.'
    }
    else {
        Write-Host '[UPDATE AVAILABLE] The latest release can overwrite the installed patch.'
    }
    exit 0
}

if ($InstalledVersion -and $InstalledVersion -eq $LatestVersion) {
    Write-Host '[OK] The installed Thai patch is already the latest release.'
    exit 0
}

$GameExe = Join-Path $GameClient 'ro3.exe'
$Running = @(Get-Process ro3 -ErrorAction SilentlyContinue | Where-Object {
    try {
        [string]::Equals(
            [System.IO.Path]::GetFullPath($_.Path),
            [System.IO.Path]::GetFullPath($GameExe),
            [System.StringComparison]::OrdinalIgnoreCase)
    }
    catch { $false }
})
if ($Running.Count -gt 0) {
    throw 'RO3 is currently running. Close the game before updating the Thai patch.'
}

$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    'RO3_Asia_Thai_Patch_Update_' + [Guid]::NewGuid().ToString('N'))
$ZipPath = Join-Path $TempRoot ([string]$Asset.name)
$ExtractRoot = Join-Path $TempRoot 'extracted'

New-Item -ItemType Directory -Path $ExtractRoot -Force | Out-Null
try {
    Write-Host "Downloading directly from GitHub Release..."
    Invoke-WebRequest -Uri ([string]$Asset.browser_download_url) -Headers $Headers -OutFile $ZipPath -UseBasicParsing

    $Downloaded = Get-Item -LiteralPath $ZipPath
    if ($Asset.size -and $Downloaded.Length -ne [long]$Asset.size) {
        throw "Downloaded ZIP size mismatch: $($Downloaded.Length) != $($Asset.size)"
    }

    $Digest = [string]$Asset.digest
    if ($Digest -match '^sha256:([0-9a-fA-F]{64})$') {
        $Expected = $matches[1].ToLowerInvariant()
        $Actual = Get-Sha256 $ZipPath
        if ($Actual -ne $Expected) {
            throw "Downloaded ZIP SHA-256 mismatch: $Actual != $Expected"
        }
        Write-Host "Verified SHA-256: $Actual"
    }

    Write-Host 'Extracting latest release...'
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $ExtractRoot -Force

    $Installers = @(Get-ChildItem -LiteralPath $ExtractRoot -Recurse -File -Filter 'Install-Thai.bat')
    if ($Installers.Count -ne 1) {
        throw "Expected one Install-Thai.bat in the latest ZIP, found $($Installers.Count)."
    }

    $LatestInstaller = $Installers[0].FullName
    Write-Host "Installing latest release over: $GameClient"
    & $LatestInstaller $GameClient '--no-pause'
    if ($LASTEXITCODE -ne 0) {
        throw "Latest installer failed with exit code $LASTEXITCODE."
    }

    $AfterVersion = Get-InstalledVersion $GameClient
    if ($AfterVersion -ne $LatestVersion) {
        throw "Install completed but marker version is '$AfterVersion' instead of '$LatestVersion'."
    }

    Write-Host ''
    Write-Host "[OK] Thai patch updated to $LatestVersion."
}
finally {
    if (Test-Path -LiteralPath $TempRoot) {
        Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
