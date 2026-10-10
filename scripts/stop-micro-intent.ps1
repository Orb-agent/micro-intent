$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$statePath = Join-Path $projectRoot '.runtime\dev-process.json'
if (-not (Test-Path -LiteralPath $statePath)) {
  Write-Host 'No development instance from this launcher is registered.'
  exit 0
}

$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
$process = Get-CimInstance Win32_Process -Filter "ProcessId = $($state.Pid)" -ErrorAction SilentlyContinue
if (-not $process) {
  Remove-Item -LiteralPath $statePath -Force
  Write-Host 'The registered process no longer exists; the record was removed.'
  exit 0
}
if ($process.Name -ne 'cmd.exe') { throw 'The recorded PID belongs to a different process type. It was not stopped.' }

$recordedStart = [DateTime]::Parse($state.StartedUtc).ToUniversalTime()
$actualStart = ([DateTime]$process.CreationDate).ToUniversalTime()
if ([Math]::Abs(($actualStart - $recordedStart).TotalSeconds) -gt 3) {
  throw 'The recorded PID has been reused by another process. It was not stopped.'
}

& taskkill.exe /PID $process.ProcessId /T /F
if ($LASTEXITCODE -ne 0) { throw 'Windows could not stop the Micro Intent process tree.' }
Remove-Item -LiteralPath $statePath -Force
Write-Host 'Stopped the process tree started by Micro Intent.'
