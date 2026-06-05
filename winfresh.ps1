$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "Not running in an elevated shell. Relaunching as administrator..." -ForegroundColor Yellow
    
    # Using single quotes makes the script block entirely literal, preventing premature parsing.
    $Arguments = @(
        "-NoExit", 
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-Command", "& { 
            Start-Transcript -Path ""$env:USERPROFILE\Desktop\winfresh_log.txt"" -Append;
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; 
                iex (irm 'https://raw.githubusercontent.com/torjacob/winfresh/refs/heads/main/winfresh.ps1');
            } catch {
                Write-Host 'An explicit crash occurred:' -ForegroundColor Red;
                $_.Exception.Message;
            } finally {
                Stop-Transcript;
            }
        }"
    )
    
    Start-Process powershell -ArgumentList $Arguments -Verb RunAs
    Exit
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
        $Properties = Get-ItemProperty -Path $Path -ErrorAction SilentlyContinue

        if($null -ne $Properties) {
            $Properties | Get-Member -MemberType NoteProperty | ForEach-Object {
                if ($KeepStartupApps -notcontains $_.Name) {
                    Remove-ItemProperty -Path $Path -Name $_.Name -ErrorAction SilentlyContinue
                }
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

Write-Host "Checking for Microsoft Store Office apps..." -ForegroundColor DarkCyan
Get-AppxPackage -AllUsers -Name "Microsoft.Office.Desktop" | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
Get-AppxPackage -AllUsers -Name "*Teams*" | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue

Write-Host "Checking for Desktop Click-to-Run Office installations..." -ForegroundColor DarkCyan

Write-Host "Clearing hidden background Office locks..." -ForegroundColor DarkCyan
$OfficeProc = @("winword", "excel", "powerpnt", "outlook", "onenote", "msaccess", "mspub", "teams", "onedrive", "officeclicktorun", "officec2rclient")
foreach ($Proc in $OfficeProc) {
    Stop-Process -Name $Proc -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 2

$OfficeUninstallKeys = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

$OfficeApps = Get-ItemProperty $OfficeUninstallKeys | Where-Object { 
    $_.DisplayName -like "*Microsoft 365*" -or 
    $_.DisplayName -like "*Microsoft Office*"
}

foreach ($App in $OfficeApps) {
    if ($App.UninstallString) {
        Write-Host "Uninstalling: $($App.DisplayName)" -ForegroundColor Yellow
        
        if ($App.QuietUninstallString) {
            if ($App.QuietUninstallString -match '"([^"]+)"\s*(.*)') {
                $ExePath = $Matches[1]
                $RawArgs = $Matches[2]
                
                $SilentArgs = "$RawArgs DisplayLevel=False forceappshutdown=True"
                Start-Process -FilePath $ExePath -ArgumentList $SilentArgs -NoNewWindow -Wait
            }
        } 
        elseif ($App.UninstallString -match "OfficeClickToRun") {
            $ProductPattern = "productstoremove=([^ ]+)"
            $ProductId = "O365ProPlusRetail"
            if ($App.UninstallString -match $ProductPattern) { $ProductId = $Matches[1] }

            $SilentArgs = "scenario=install scenariosubtype=ARP sourcetype=None productstoremove=$ProductId culture=en-us DisplayLevel=False forceappshutdown=True"
            Start-Process "C:\Program Files\Common Files\microsoft shared\ClickToRun\OfficeClickToRun.exe" -ArgumentList $SilentArgs -NoNewWindow -Wait
        } 
        else {
            $CleanCmd = $App.UninstallString -replace "msiexec.exe", "" -replace "/I", "" -replace "/X", ""
            $CleanCmd = $CleanCmd.Trim()
            Start-Process "msiexec.exe" -ArgumentList "/X $CleanCmd /qn /norestart" -NoNewWindow -Wait
        }
    }
}

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
    Write-Host "Executing WinUtil tweaks in an isolated process..." -ForegroundColor Yellow
    
    $WinUtilArgs = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-Command", "& { & ([ScriptBlock]::Create((irm 'https://christitus.com/win'))) -Run -NoUi -Config '$WinUtilConfigPath' }"
    )
    
    Start-Process powershell -ArgumentList $WinUtilArgs -NoNewWindow -Wait

    Write-Host "Reviving Windows Explorer shell..." -ForegroundColor Green
    Start-Process "explorer.exe"
    Start-Sleep -Seconds 3
} else {
    Write-Host "Config download failed, running basic web script in isolation..." -ForegroundColor Yellow
    $FallbackArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", "irm 'https://christitus.com/win' | iex")
    Start-Process powershell -ArgumentList $FallbackArgs -NoNewWindow -Wait
}

Write-Host "Running ShutUp10++..." -ForegroundColor Cyan

$OOCfgUrl = "https://raw.githubusercontent.com/torjacob/winfresh/refs/heads/main/oosu10pp.cfg"
$OOExeUrl = "https://dl5.oo-software.com/files/ooshutup10/OOSU10.exe"

$OODir = "C:\OOSu10"
New-Item -ItemType Directory -Path $OODir -Force | Out-Null

Write-Host "Downloading fresh application binaries..." -ForegroundColor DarkCyan
try {
    Invoke-WebRequest -Uri $OOExeUrl -OutFile "$OODir\oosu10pp.exe" -ErrorAction SilentlyContinue
    Invoke-WebRequest -Uri $OOCfgUrl -OutFile "$OODir\oosu10pp_config.cfg" -ErrorAction SilentlyContinue
    
    Start-Sleep -Seconds 2
} catch {
    Write-Warning "Failed downloading ShutUp10 assets: $_"
}

if (Test-Path "$OODir\oosu10pp.exe") {
    if (Test-Path "$OODir\oosu10pp_config.cfg") {
        Write-Host "Applying ShutUp10++ configuration quietly..." -ForegroundColor Yellow
        Start-Process -FilePath "$OODir\oosu10pp.exe" -ArgumentList "`"$OODir\oosu10pp_config.cfg`" /g /quiet" -NoNewWindow -Wait
    } else {
        Write-Host "Config not found, falling back to basic factory defaults..." -ForegroundColor Yellow
        Start-Process -FilePath "$OODir\oosu10pp.exe" -ArgumentList "/o /quiet" -NoNewWindow -Wait
    }
} else {
    Write-Error "Execution aborted: Executable binary is missing or unreadable."
}

Write-Host "Deleting temporary files..." -ForegroundColor Cyan

if (Test-Path $OODir) { Remove-Item -Path $OODir -Recurse -Force -ErrorAction SilentlyContinue }
if (Test-Path $WinUtilConfigPath) { Remove-Item -Path $WinUtilConfigPath -Force -ErrorAction SilentlyContinue }

Get-ChildItem -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Get-ChildItem -Path "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "Script complete!" -ForegroundColor Green
