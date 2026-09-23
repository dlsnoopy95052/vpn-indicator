# install-startup.ps1
# Adds a "VPN Indicator" shortcut to your Startup folder so it runs at sign-in, then starts it now.
# To uninstall: delete "VPN Indicator.lnk" from shell:startup and choose Exit on the tray icon.

$script = Join-Path $PSScriptRoot 'vpn-indicator.ps1'
$ps     = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$argsLine = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File `"$script`""

$lnkPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'VPN Indicator.lnk'
$shell = New-Object -ComObject WScript.Shell
$lnk = $shell.CreateShortcut($lnkPath)
$lnk.TargetPath       = $ps
$lnk.Arguments        = $argsLine
$lnk.WorkingDirectory = $PSScriptRoot
$lnk.WindowStyle      = 7   # minimized
$lnk.Description      = 'VPN status tray indicator'
$lnk.Save()

Start-Process -FilePath $ps -ArgumentList $argsLine -WindowStyle Hidden
Write-Host "Installed startup shortcut: $lnkPath"
Write-Host "VPN Indicator is now running in the tray. Pin it via Settings > Personalization > Taskbar > Other system tray icons."
