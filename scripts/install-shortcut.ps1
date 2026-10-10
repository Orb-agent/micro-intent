$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$desktopPath = [Environment]::GetFolderPath('Desktop')
if (-not $desktopPath) { throw 'Could not find the Windows desktop folder.' }

$shortcutPath = Join-Path $desktopPath 'Micro Intent.lnk'
$powershellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$launcherPath = Join-Path $PSScriptRoot 'start-micro-intent.ps1'
$shell = New-Object -ComObject WScript.Shell
try {
  $shortcut = $shell.CreateShortcut($shortcutPath)
  $shortcut.TargetPath = $powershellPath
  $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$launcherPath`" -OpenApp"
  $shortcut.WorkingDirectory = $projectRoot
  $shortcut.Description = 'Start Micro Intent and open the local app.'
  $shortcut.Save()
} finally {
  [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
}

Write-Host "Shortcut created: $shortcutPath"
