$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "Not running in an elevated shell. Relaunching as administrator..." -ForegroundColor Yellow
    
    $Arguments = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-Command", "& { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; iex (irm 'https://raw.githubusercontent.com/torjacob/winfresh/refs/heads/main/winfresh.ps1') }"
    )
    
    Start-Process powershell -ArgumentList $Arguments -Verb RunAs
    exit
}

Write-Host "Running as administrator." -ForegroundColor Green

Write-Host "Removing old user profiles..." -ForegroundColor Cyan

$KeepUsers = @("tmpenps")

$KeepUsers += $env:USERNAME

Get-CimInstance -Class Win32_UserProfile | Where-Object {
    $_.Special -eq $false -and 
    $_.LocalPath -notlike "*\Public" -and 
    $_.LocalPath -notlike "*\Default" -and
    
    $KeepUsers -notcontains [System.IO.Path]::GetFileName($_.LocalPath)

} | Remove-CimInstance -ErrorAction SilentlyContinue

Write-Host "Removing any orphaned folders..." -ForegroundColor Cyan

Get-ChildItem -Path "C:\Users" -Directory | Where-Object {
    $_.Name -notmatch "Public|Default" -and $KeepUsers -notcontains $_.Name
} | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "Removing unneeded startup apps..." -ForegroundColor Cyan

$KeepStartupApps = @("NRKFiler", "F5_SAM_Client")

$RegPaths = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run",
    "HKCU:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"
)

foreach ($Path in $RegPaths) {
    if (Test-Path $Path) {
        Get-ItemProperty -Path $Path | Get-Member -MemberType NoteProperty | ForEach-Object {
            if ($KeepStartupApps -notcontains $_.Name) {
                Remove-ItemProperty -Path $Path -Name $_.Name -ErrorAction SilentlyContinue
            }
        }
    }
}

Write-Host "Cleaning public desktop..." -ForegroundColor Cyan

$PublicDesktop = "C:\Users\Public\Desktop"
if (Test-Path $PublicDesktop) {
    Get-ChildItem -Path $PublicDesktop -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Uninstalling Microsoft Office, Teams, and OneDrive" -ForegroundColor Cyan

Get-Package -Name "*Microsoft Office*" -ErrorAction SilentlyContinue | Uninstall-Package -Force -ErrorAction SilentlyContinue
Get-Package -Name "*Microsoft Teams*" -ErrorAction SilentlyContinue | Uninstall-Package -Force -ErrorAction SilentlyContinue
Get-AppxPackage -AllUsers -Name "*Teams*" | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue

$OneDrivePaths = @(
    "$env:SystemRoot\System32\OneDriveSetup.exe",
    "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
)

foreach ($Path in $OneDrivePaths) {
    if (Test-Path $Path) {
        Start-Process -FilePath $Path -ArgumentList "/uninstall" -NoNewWindow -Wait -ErrorAction SilentlyContinue
    }
}

Write-Host "Running WinUtil..." -ForegroundColor Cyan

$WinUtilConfigUrl = "https://raw.githubusercontent.com/torjacob/winfresh/refs/heads/main/winutil.json"
$WinUtilConfigPath = "$env:TEMP\winutil_config.json"

Invoke-WebRequest -Uri $WinUtilConfigUrl -OutFile $WinUtilConfigPath -ErrorAction SilentlyContinue

if (Test-Path $WinUtilConfigPath) {
    & ([ScriptBlock]::Create((irm "https://christitus.com/win"))) -Run -Config $WinUtilConfigPath
} else {
    irm "https://christitus.com/win" | iex
}

Write-Host "Running ShutUp10++..." -ForegroundColor Cyan

$OOCfgUrl = "https://raw.githubusercontent.com/torjacob/winfresh/refs/heads/main/oosu10pp.cfg"
$OOExeUrl = "https://www.oo-software.com/en/download/current/ooshutup10"

$OODir = "$env:TEMP\OOSu10"
New-Item -ItemType Directory -Path $OODir -Force | Out-Null

Invoke-WebRequest -Uri $OOExeUrl -OutFile "$OODir\oosu10pp.exe"
Invoke-WebRequest -Uri $OOCfgUrl -OutFile "$OODir\oosu10pp_config.cfg"

if (Test-Path "$OODir\oosu10pp_config.cfg") {
    Start-Process -FilePath "$OODir\oosu10pp.exe" -ArgumentList "`"$OODir\oosu10pp_config.cfg`" /g /quiet" -NoNewWindow -Wait
} else {
    Write-Host "Config not found, falling back to GUI..." -ForegroundColor Yellow
    Start-Process -FilePath "$OODir\oosu10pp.exe" -ArgumentList "/o /quiet" -NoNewWindow -Wait
}

Write-Host "Deleting temporary files..." -ForegroundColor Cyan

if (Test-Path $OODir) { Remove-Item -Path $OODir -Recurse -Force -ErrorAction SilentlyContinue }
if (Test-Path $WinUtilConfigPath) { Remove-Item -Path $WinUtilConfigPath -Force -ErrorAction SilentlyContinue }

Get-ChildItem -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Get-ChildItem -Path "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "Script complete!" -ForegroundColor Green
