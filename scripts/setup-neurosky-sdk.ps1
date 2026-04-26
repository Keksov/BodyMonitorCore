param(
    [string]$SdkRoot
)

$ErrorActionPreference = 'Stop'

$bodyMonitorRoot = Resolve-Path (Join-Path $PSScriptRoot "..\cli")
$streamTarget = Join-Path $bodyMonitorRoot "vendor\StreamSDK"
$eegTarget = Join-Path $bodyMonitorRoot "vendor\EEGAlgoSDK"
$mindWaveVendorRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\..\VendorsCore\MindWave"))
$mindWaveDownloadScript = Join-Path $mindWaveVendorRoot "scripts\win_sdk_download.bat"

$candidates = @()
if ($SdkRoot) {
    $candidates += $SdkRoot
}
if ($env:NEUROSKY_SDK_ROOT) {
    $candidates += $env:NEUROSKY_SDK_ROOT
}
$candidates += "C:\projects\MindWave.bak2\pas"
$candidates += "C:\projects\MindWave.bak\pas"
$candidates += "C:\projects\MindWave\archive\Windows Developer Tools 3.2"

$resolvedRoot = $null
foreach ($candidate in $candidates) {
    if (-not $candidate) {
        continue
    }
    $streamPas = Join-Path $candidate "StreamSDK\ThinkGearSDK.pas"
    $streamLib = Join-Path $candidate "StreamSDK\libimpThinkGearSDK.a"
    $eegPas = Join-Path $candidate "EEGAlgoSDK\EEGAlgoSDK.pas"
    $eegLib = Join-Path $candidate "EEGAlgoSDK\libimpEEGAlgoSDK.a"
    if ((Test-Path $streamPas) -and (Test-Path $streamLib) -and (Test-Path $eegPas) -and (Test-Path $eegLib)) {
        $resolvedRoot = $candidate
        break
    }
}

if (-not $resolvedRoot) {
    throw "Cannot find a valid NeuroSky SDK root. Provide -SdkRoot pointing to a folder that contains StreamSDK and EEGAlgoSDK subfolders."
}

if (-not (Test-Path $streamTarget)) {
    New-Item -ItemType Directory -Path $streamTarget | Out-Null
}
if (-not (Test-Path $eegTarget)) {
    New-Item -ItemType Directory -Path $eegTarget | Out-Null
}

Copy-Item -Force (Join-Path $resolvedRoot "StreamSDK\ThinkGearSDK.pas") (Join-Path $streamTarget "ThinkGearSDK.pas")
Copy-Item -Force (Join-Path $resolvedRoot "StreamSDK\libimpThinkGearSDK.a") (Join-Path $streamTarget "libimpThinkGearSDK.a")
Copy-Item -Force (Join-Path $resolvedRoot "EEGAlgoSDK\EEGAlgoSDK.pas") (Join-Path $eegTarget "EEGAlgoSDK.pas")
Copy-Item -Force (Join-Path $resolvedRoot "EEGAlgoSDK\libimpEEGAlgoSDK.a") (Join-Path $eegTarget "libimpEEGAlgoSDK.a")

Write-Host "NeuroSky SDK source/import-lib files installed to BodyMonitorCore from: $resolvedRoot"
Write-Host "NeuroSky runtime DLLs are sourced from: $mindWaveVendorRoot"
Write-Host "Download them with: $mindWaveDownloadScript"
