<#
.SYNOPSIS
Builds, installs and runs the repro (example\ModalRaceRepro.csproj) on a connected Android device or emulator, prints the result of each run
and optionally saves a screenshot and the log line per run. PowerShell version of run.sh (Windows, also works with pwsh on macOS/Linux).
Run it from the repository root.

.PARAMETER Delays
Delays (ms) between PushModalAsync and PopModalAsync, one run per value. Default: 0 and 1000.

.PARAMETER SkipBuild
Does not build/install again.

.PARAMETER Save
Directory (relative to the repository root) where delay-<ms>ms.png and delay-<ms>ms-log.txt of each run are saved.

.PARAMETER MauiVersion
Builds with another Microsoft.Maui.Controls version than the one in the csproj.

.EXAMPLE
.\run.ps1
.\run.ps1 0 50 150 400 1000
.\run.ps1 -Save results\<dir> 0 50 150 400 1000
.\run.ps1 -MauiVersion 10.0.20 0
.\run.ps1 -SkipBuild 0

Environment (optional):
  ADB       path to adb (default: adb from PATH, otherwise %LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe, ~/Library/Android/sdk/platform-tools/adb on macOS)
  DEVICE    adb serial (default: the first connected device)
  WAIT_S    how long to wait for the result of one run, default 30

If scripts are blocked: powershell -ExecutionPolicy Bypass -File .\run.ps1 0 1000
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [switch]$SkipBuild,
    [string]$Save = "",
    [string]$MauiVersion = "",
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$Delays
)
$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
Set-Location $Root

if (-not $Delays -or $Delays.Count -eq 0) { $Delays = @("0", "1000") }
if ($Save -and -not [System.IO.Path]::IsPathRooted($Save)) { $Save = Join-Path $Root $Save }   # -Save is relative to the repository root

# adb
$Adb = $env:ADB
if (-not $Adb) {
    $cmd = Get-Command adb -ErrorAction SilentlyContinue
    if ($cmd) { $Adb = $cmd.Source }
    elseif ($env:LOCALAPPDATA -and (Test-Path (Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe"))) { $Adb = Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe" }
    elseif (Test-Path (Join-Path $HOME "Library/Android/sdk/platform-tools/adb")) { $Adb = Join-Path $HOME "Library/Android/sdk/platform-tools/adb" }
    else { throw "adb not found. Add it to PATH or set the ADB environment variable." }
}

$Device = $env:DEVICE
if (-not $Device) {
    $Device = (& $Adb devices | Select-Object -Skip 1 | ForEach-Object { if ($_ -match '^(\S+)\s+device\s*$') { $Matches[1] } } | Select-Object -First 1)
}
if (-not $Device) { throw "no Android device connected" }
$Pkg = "com.companyname.modalracerepro"
$WaitS = if ($env:WAIT_S) { [int]$env:WAIT_S } else { 30 }

function Invoke-Adb { & $Adb -s $Device @args }

if (-not $SkipBuild) {
    $buildArgs = @("build", "example/ModalRaceRepro.csproj", "-f", "net10.0-android", "-t:Install", "-p:AndroidAttachDebugger=false", "-p:AdbTarget=-s $Device", "--nologo", "-v:q")
    if ($MauiVersion) { $buildArgs += "-p:MauiVersion=$MauiVersion" }
    & dotnet @buildArgs
    if ($LASTEXITCODE -ne 0) { throw "dotnet build failed (exit code $LASTEXITCODE)" }
}

$Activity = ((Invoke-Adb shell cmd package resolve-activity --brief $Pkg) | Select-Object -Last 1).Trim()
if ($Save) { New-Item -ItemType Directory -Force -Path $Save | Out-Null }

foreach ($d in $Delays) {
    Invoke-Adb shell input keyevent KEYCODE_WAKEUP | Out-Null
    Invoke-Adb shell am force-stop $Pkg | Out-Null
    Invoke-Adb logcat -c | Out-Null
    Invoke-Adb shell am start -n $Activity --ei delay_ms $d | Out-Null

    $line = ""
    for ($i = 0; $i -lt $WaitS; $i++) {
        $hit = (Invoke-Adb logcat -d) | Where-Object { $_ -like '*`[REPRO`]*' } | Select-Object -Last 1
        if ($hit) { $line = ($hit -replace '^.*\[REPRO\]', '[REPRO]').Trim(); break }
        Start-Sleep -Seconds 1
    }
    Start-Sleep -Seconds 1

    $windows = @((Invoke-Adb shell dumpsys window windows) | Where-Object { $_ -match "Window #\d+ Window.*$([regex]::Escape($Pkg))" }).Count
    if (-not $line) { $line = "[REPRO] no result within $WaitS s" }
    Write-Host "$line  (app windows: $windows)"

    if ($Save) {
        # no "adb exec-out screencap > file": PowerShell redirection would corrupt the binary PNG, so take it on the device and pull it
        Invoke-Adb shell screencap -p /sdcard/modalrepro.png | Out-Null
        Invoke-Adb pull /sdcard/modalrepro.png (Join-Path $Save "delay-${d}ms.png") | Out-Null
        Invoke-Adb shell rm /sdcard/modalrepro.png | Out-Null
        Set-Content -Path (Join-Path $Save "delay-${d}ms-log.txt") -Value @($line, "app windows (dumpsys window): $windows") -Encoding utf8
    }
}
