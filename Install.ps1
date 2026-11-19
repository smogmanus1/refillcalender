<#
  Install.ps1 - installer for RefillCalendar
  Tracks prescription refill dates and exports reminders as an .ics calendar file.

  Easiest: double-click Install.cmd (same folder).
  Or from PowerShell:   .\Install.ps1
  Remove it again:      Settings > Apps > RefillCalendar > Uninstall   (or  .\Install.ps1 -Uninstall)

  Options:
    -InstallDir <path>   where to install (default: %LOCALAPPDATA%\Programs\RefillCalendar)
    -NoDesktop           do not create a Desktop shortcut
    -NoStartMenu         do not create Start menu shortcuts
    -Startup / -NoStartup  force the "run when I sign in" shortcut on or off
    -NoLaunch            do not start the program when the install finishes

  No administrator rights are needed for RefillCalendar itself. If AutoHotkey v2 is not
  installed yet, this script installs it first (Windows may ask permission once).
  Works from a downloaded ZIP, or straight from GitHub (see README).
  Part of RefillCalendar (MIT) - Brad Schrunk & Claude (Anthropic)
#>
param(
    [switch]$Uninstall,
    [string]$InstallDir = '',
    [switch]$NoDesktop,
    [switch]$NoStartMenu,
    [switch]$Startup,
    [switch]$NoStartup,
    [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'

$App = @{
    Name           = 'RefillCalendar'
    Version        = '1.0.0'
    Repo           = 'smogmanus1/refillcalender'
    Branch         = 'main'
    Main           = 'RefillCalendar.ahk'
    DefaultDir     = '%LOCALAPPDATA%\Programs\RefillCalendar'
    Include        = @('RefillCalendar.ahk', 'RefillCalendar.example.ini', 'README.md', 'LICENSE')
    KeepIfExists   = @()
    StartupDefault = $false
    Tips           = @('Open Refill Calendar from the Start menu, press Win+Alt+R, or type ccrefill.', 'Your list is saved in %AppData%\RefillCalendar and is never touched by install or uninstall.')
}

if (-not $InstallDir) { $InstallDir = [Environment]::ExpandEnvironmentVariables($App.DefaultDir) }

function Write-Step($m) { Write-Host "  ... $m" -ForegroundColor Cyan }
function Write-Ok($m)   { Write-Host "  OK  $m" -ForegroundColor Green }
function Write-Note($m) { Write-Host "  !   $m" -ForegroundColor Yellow }

function Find-Ahk {
    $exeName = 'AutoHotkey32.exe'
    if ([Environment]::Is64BitOperatingSystem) { $exeName = 'AutoHotkey64.exe' }
    $dirs = @()
    foreach ($k in 'HKLM:\SOFTWARE\AutoHotkey', 'HKLM:\SOFTWARE\WOW6432Node\AutoHotkey', 'HKCU:\SOFTWARE\AutoHotkey') {
        try {
            $d = (Get-ItemProperty -Path $k -ErrorAction Stop).InstallDir
            if ($d) { $dirs += $d }
        } catch { }
    }
    $dirs += (Join-Path $env:ProgramFiles 'AutoHotkey')
    $dirs += (Join-Path $env:LOCALAPPDATA 'Programs\AutoHotkey')
    foreach ($d in $dirs) {
        $p = Join-Path $d "v2\$exeName"
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

function Install-Ahk {
    Write-Step 'AutoHotkey v2 is not installed - installing it now (Windows may ask permission)'
    # Offline first: an AutoHotkey setup file kept next to this installer (or in the folder above it, e.g. on a USB stick).
    $localDirs = @()
    if ($PSScriptRoot) {
        $parent = Split-Path -Parent $PSScriptRoot
        $localDirs += @{ Path = $PSScriptRoot; Deep = $false }
        $localDirs += @{ Path = (Join-Path $PSScriptRoot 'Installers'); Deep = $true }
        if ($parent) {
            $localDirs += @{ Path = $parent; Deep = $false }
            $localDirs += @{ Path = (Join-Path $parent 'PCMigrate\Installers'); Deep = $true }
        }
    }
    foreach ($ld in $localDirs) {
        if (-not (Test-Path -LiteralPath $ld.Path)) { continue }
        foreach ($pat in 'AutoHotkey*setup*.exe', 'ahk-v2*.exe') {
            $f = Get-ChildItem -LiteralPath $ld.Path -Filter $pat -File -Recurse:$ld.Deep -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($f) {
                Write-Step "Using $($f.Name) from $($f.DirectoryName)"
                Start-Process -FilePath $f.FullName -ArgumentList '/silent' -Wait
                $p = Find-Ahk
                if ($p) { return $p }
            }
        }
    }
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($winget) {
        try {
            & winget.exe install --id AutoHotkey.AutoHotkey -e --silent --accept-package-agreements --accept-source-agreements | Out-Host
        } catch { }
        $p = Find-Ahk
        if ($p) { return $p }
    }
    Write-Step 'Downloading the AutoHotkey installer from autohotkey.com'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $setup = Join-Path $env:TEMP 'ahk-v2-setup.exe'
    Invoke-WebRequest -UseBasicParsing -Uri 'https://www.autohotkey.com/download/ahk-v2.exe' -OutFile $setup
    Start-Process -FilePath $setup -ArgumentList '/silent' -Wait
    return (Find-Ahk)
}

function Get-SourceDir {
    # Files next to this script (downloaded ZIP / cloned repo), else download from GitHub.
    $here = $PSScriptRoot
    if ($here -and (Test-Path -LiteralPath (Join-Path $here $App.Main))) {
        return @{ Dir = $here; Temp = $null }
    }
    Write-Step "Downloading $($App.Name) from GitHub"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $tmp = Join-Path $env:TEMP ("{0}-install-{1}" -f $App.Name, [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    $zip = Join-Path $tmp 'source.zip'
    Invoke-WebRequest -UseBasicParsing -Uri ("https://github.com/{0}/archive/refs/heads/{1}.zip" -f $App.Repo, $App.Branch) -OutFile $zip
    Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force
    $root = Get-ChildItem -LiteralPath $tmp -Directory | Select-Object -First 1
    if (-not $root -or -not (Test-Path -LiteralPath (Join-Path $root.FullName $App.Main))) {
        throw 'The download did not contain the expected files.'
    }
    return @{ Dir = $root.FullName; Temp = $tmp }
}

function Stop-Running([string]$dir) {
    try {
        Get-CimInstance Win32_Process -Filter "Name LIKE 'AutoHotkey%'" |
            Where-Object { $_.CommandLine -and $_.CommandLine -like "*$dir\*" } |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    } catch { }
}

function New-AppShortcut([string]$path, [string]$target, [string]$arguments, [string]$workDir, [string]$desc, [string]$icon) {
    $sh  = New-Object -ComObject WScript.Shell
    $lnk = $sh.CreateShortcut($path)
    $lnk.TargetPath       = $target
    $lnk.Arguments        = $arguments
    $lnk.WorkingDirectory = $workDir
    $lnk.Description      = $desc
    if ($icon) { $lnk.IconLocation = $icon }
    $lnk.Save()
}

$StartMenuDir = [Environment]::GetFolderPath('Programs')
$DesktopDir   = [Environment]::GetFolderPath('Desktop')
$StartupDir   = [Environment]::GetFolderPath('Startup')
$UninstallKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$($App.Name)"

function Invoke-AppInstall {
    Write-Host ''
    Write-Host "  $($App.Name) $($App.Version) - installer" -ForegroundColor White
    Write-Host ''

    $ahk = Find-Ahk
    if ($ahk) {
        Write-Ok 'AutoHotkey v2 is installed'
    } else {
        $ahk = Install-Ahk
        if (-not $ahk) {
            throw 'Could not install AutoHotkey v2. Install it from https://www.autohotkey.com and run this installer again.'
        }
        Write-Ok 'AutoHotkey v2 installed'
    }

    $srcInfo = Get-SourceDir
    $src = $srcInfo.Dir

    Stop-Running $InstallDir
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

    foreach ($item in $App.Include) {
        $from = Join-Path $src $item
        if (-not (Test-Path -LiteralPath $from)) { Write-Note "not found in download: $item"; continue }
        $to = Join-Path $InstallDir $item
        if ((Test-Path -LiteralPath $to) -and ($App.KeepIfExists -contains $item)) {
            Write-Note "keeping your existing $item"
            continue
        }
        if ((Get-Item -LiteralPath $from).PSIsContainer) {
            New-Item -ItemType Directory -Path $to -Force | Out-Null
            Copy-Item -Path (Join-Path $from '*') -Destination $to -Recurse -Force
        } else {
            Copy-Item -LiteralPath $from -Destination $to -Force
        }
    }
    # The installer itself goes along so it can uninstall later.
    $selfSrc = Join-Path $src 'Install.ps1'
    if (Test-Path -LiteralPath $selfSrc) { Copy-Item -LiteralPath $selfSrc -Destination (Join-Path $InstallDir 'Install.ps1') -Force }
    try { Get-ChildItem -LiteralPath $InstallDir -Recurse -File | Unblock-File } catch { }
    Write-Ok "Files copied to $InstallDir"

    $mainPath = Join-Path $InstallDir $App.Main
    $argLine  = '"' + $mainPath + '"'
    $uninstArgs = '-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $InstallDir 'Install.ps1') + '" -Uninstall'

    if (-not $NoStartMenu) {
        New-AppShortcut (Join-Path $StartMenuDir "$($App.Name).lnk") $ahk $argLine $InstallDir $App.Name $ahk
        New-AppShortcut (Join-Path $StartMenuDir "Uninstall $($App.Name).lnk") 'powershell.exe' $uninstArgs $InstallDir "Remove $($App.Name)" ''
        Write-Ok 'Start menu shortcuts created'
    }
    if (-not $NoDesktop) {
        New-AppShortcut (Join-Path $DesktopDir "$($App.Name).lnk") $ahk $argLine $InstallDir $App.Name $ahk
        Write-Ok 'Desktop shortcut created'
    }
    $wantStartup = $App.StartupDefault
    if ($Startup)   { $wantStartup = $true }
    if ($NoStartup) { $wantStartup = $false }
    $startupLnk = Join-Path $StartupDir "$($App.Name).lnk"
    if ($wantStartup) {
        New-AppShortcut $startupLnk $ahk $argLine $InstallDir $App.Name $ahk
        Write-Ok "$($App.Name) will start when you sign in"
    } elseif (Test-Path -LiteralPath $startupLnk) {
        Remove-Item -LiteralPath $startupLnk -Force -ErrorAction SilentlyContinue
    }

    # Entry in Settings > Apps so it can be removed the normal way.
    New-Item -Path $UninstallKey -Force | Out-Null
    $props = @{
        DisplayName     = $App.Name
        DisplayVersion  = $App.Version
        Publisher       = 'Brad Schrunk'
        InstallLocation = $InstallDir
        URLInfoAbout    = "https://github.com/$($App.Repo)"
        UninstallString = ('powershell.exe ' + $uninstArgs)
        NoModify        = 1
        NoRepair        = 1
    }
    foreach ($n in $props.Keys) {
        $type = 'String'
        if ($props[$n] -is [int]) { $type = 'DWord' }
        New-ItemProperty -Path $UninstallKey -Name $n -Value $props[$n] -PropertyType $type -Force | Out-Null
    }
    Write-Ok 'Listed in Settings > Apps'

    if ($srcInfo.Temp) { Remove-Item -LiteralPath $srcInfo.Temp -Recurse -Force -ErrorAction SilentlyContinue }

    if (-not $NoLaunch) {
        Start-Process -FilePath $ahk -ArgumentList $argLine -WorkingDirectory $InstallDir
        Write-Ok "$($App.Name) started"
    }

    Write-Host ''
    Write-Host "  $($App.Name) is installed." -ForegroundColor Green
    foreach ($t in $App.Tips) { Write-Host "    - $t" }
    Write-Host ''
}

function Invoke-AppUninstall {
    Write-Host ''
    Write-Host "  Removing $($App.Name)" -ForegroundColor White
    $dir = $InstallDir
    try {
        $loc = (Get-ItemProperty -Path $UninstallKey -ErrorAction Stop).InstallLocation
        if ($loc) { $dir = $loc }
    } catch { }

    Stop-Running $dir
    foreach ($p in @((Join-Path $StartMenuDir "$($App.Name).lnk"),
                     (Join-Path $StartMenuDir "Uninstall $($App.Name).lnk"),
                     (Join-Path $DesktopDir "$($App.Name).lnk"),
                     (Join-Path $StartupDir "$($App.Name).lnk"))) {
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue }
    }
    Remove-Item -Path $UninstallKey -Recurse -Force -ErrorAction SilentlyContinue

    # Only delete a folder that really is this app's install folder.
    if ((Test-Path -LiteralPath $dir) -and (Test-Path -LiteralPath (Join-Path $dir $App.Main))) {
        Start-Process -FilePath 'cmd.exe' -ArgumentList ('/c timeout /t 3 /nobreak >nul & rmdir /s /q "{0}"' -f $dir) -WindowStyle Hidden
        Write-Ok "Removed $dir"
    } else {
        Write-Note "Install folder not found or not recognised - left alone: $dir"
    }
    Write-Host ''
    Write-Host "  $($App.Name) has been removed." -ForegroundColor Green
    Write-Note 'Your saved list in %AppData%\RefillCalendar was kept.'
    Write-Host ''
}

$exitCode = 0
try {
    if ($Uninstall) { Invoke-AppUninstall } else { Invoke-AppInstall }
} catch {
    Write-Host ''
    Write-Host "  Install failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ''
    $exitCode = 1
}
# Only pause/exit when run as a file; when pasted or piped from GitHub, leave the window alone.
if ($PSCommandPath) {
    if ($Uninstall) { Read-Host '  Press Enter to close' | Out-Null }
    exit $exitCode
}
