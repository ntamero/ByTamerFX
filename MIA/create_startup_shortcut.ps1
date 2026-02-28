$startupPath = [Environment]::GetFolderPath('Startup')
Write-Host "Startup folder: $startupPath"

$shortcutPath = Join-Path $startupPath 'MIA_BytamerFX.lnk'
$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut($shortcutPath)
$Shortcut.TargetPath = 'wscript.exe'
$Shortcut.Arguments = '"D:\CLAUDE\FXAGENT\start_mia_silent.vbs"'
$Shortcut.WorkingDirectory = 'D:\CLAUDE\FXAGENT'
$Shortcut.Description = 'MIA BytamerFX Dashboard + Telegram Bot'
$Shortcut.WindowStyle = 7
$Shortcut.Save()

Write-Host "Kisayol olusturuldu: $shortcutPath"
