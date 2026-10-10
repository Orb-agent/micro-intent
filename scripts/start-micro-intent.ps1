param(
  [switch]$OpenApp
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$runtimeDir = Join-Path $projectRoot '.runtime'
$statePath = Join-Path $runtimeDir 'dev-process.json'
$logPath = Join-Path $runtimeDir 'dev.log'
$frontendUrl = 'http://localhost:5173/'
$apiUrl = 'http://127.0.0.1:3001/api/status'

function Test-Frontend([string]$url, [int]$timeoutSeconds = 5) {
  try {
    $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec $timeoutSeconds
    return $response.StatusCode -eq 200 -and $response.Content -match '<title>Micro Intent'
  } catch { return $false }
}

function Test-Api([int]$timeoutSeconds = 5) {
  try {
    $response = Invoke-RestMethod -Uri $apiUrl -TimeoutSec $timeoutSeconds
    return ($null -ne $response.PSObject.Properties['googleConfigured']) -and ($null -ne $response.PSObject.Properties['modelConfigured'])
  } catch { return $false }
}

function Open-App([string]$url) {
  if ($OpenApp) { Start-Process $url }
}

New-Item -ItemType Directory -Path $runtimeDir -Force | Out-Null

# If this launcher already owns a live process, reuse its selected Vite port.
$priorState = $null
if (Test-Path -LiteralPath $statePath) {
  try { $priorState = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json } catch { $priorState = $null }
}
if ($priorState -and $priorState.Pid) {
  $priorProcess = Get-CimInstance Win32_Process -Filter "ProcessId = $($priorState.Pid)" -ErrorAction SilentlyContinue
  if ($priorProcess -and $priorProcess.Name -eq 'cmd.exe') {
    $recordedStart = [DateTime]::Parse($priorState.StartedUtc).ToUniversalTime()
    $actualStart = ([DateTime]$priorProcess.CreationDate).ToUniversalTime()
    if ([Math]::Abs(($actualStart - $recordedStart).TotalSeconds) -le 3) {
      if ((Test-Frontend $priorState.FrontendUrl) -and (Test-Api)) {
        Write-Host "Micro Intent is already available at $($priorState.FrontendUrl)."
        Open-App $priorState.FrontendUrl
        exit 0
      }
      throw 'A Micro Intent launcher is already running, but one service is not responding. Run scripts\stop-micro-intent.ps1 and start it again.'
    }
  }
  Remove-Item -LiteralPath $statePath -Force
}

$defaultFrontendReady = Test-Frontend $frontendUrl
$apiReady = Test-Api
if ($defaultFrontendReady -and $apiReady) {
  Write-Host "Micro Intent is already available at $frontendUrl."
  Open-App $frontendUrl
  exit 0
}

# Reuse a healthy half of the app and start only the missing half.
$npmCommand = Get-Command npm.cmd -ErrorAction SilentlyContinue
if (-not $npmCommand) { throw 'npm.cmd was not found. Install Node.js and try again.' }
if ($defaultFrontendReady) {
  $npmScript = 'npm run dev:backend'
  $runMode = 'backend'
  Write-Host 'The web app is already running; starting only the missing API.'
} elseif ($apiReady) {
  $npmScript = 'npm run dev:frontend'
  $runMode = 'frontend'
  Write-Host 'The API is already running; starting only the missing web app.'
} else {
  $npmScript = 'npm run dev'
  $runMode = 'all'
}

# A process on the API port that is not this app is unsafe to reuse: the web proxy
# targets that fixed port, so fail clearly instead of sending requests elsewhere.
if (-not $apiReady) {
  $apiPortBusy = Get-NetTCPConnection -State Listen -LocalPort 3001 -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($apiPortBusy) { throw 'Port 3001 is occupied by a service that does not appear to be Micro Intent. Free the port before starting the app.' }
}

if (-not $defaultFrontendReady) {
  $webPortBusy = Get-NetTCPConnection -State Listen -LocalPort 5173 -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($webPortBusy) { throw 'Port 5173 is occupied by a site that does not appear to be Micro Intent. Free the port before starting the app.' }
}

if (Test-Path -LiteralPath $logPath) { Remove-Item -LiteralPath $logPath -Force }
$commandLine = "$npmScript > `"$logPath`" 2>&1"
$devProcess = Start-Process -FilePath $env:ComSpec `
  -ArgumentList @('/c', $commandLine) `
  -WorkingDirectory $projectRoot `
  -WindowStyle Hidden `
  -PassThru

$createdUtc = [DateTime]::UtcNow
$actualFrontendUrl = $frontendUrl
$deadline = [DateTime]::UtcNow.AddSeconds(13)
$ready = $false
while ([DateTime]::UtcNow -lt $deadline) {
  $webReady = if ($runMode -eq 'backend') { $defaultFrontendReady } else { Test-Frontend $actualFrontendUrl 1 }
  $apiReady = if ($runMode -eq 'frontend') { $apiReady } else { Test-Api 1 }
  if ($webReady -and $apiReady) { $ready = $true; break }
  Start-Sleep -Milliseconds 400
}

if (-not $ready) {
  & taskkill.exe /PID $devProcess.Id /T /F 2>$null | Out-Null
  Write-Host "Log: $logPath"
  throw 'Micro Intent did not respond within 15 seconds. Check the log above and ports 5173/3001.'
}

$processInfo = Get-CimInstance Win32_Process -Filter "ProcessId = $($devProcess.Id)" -ErrorAction SilentlyContinue
$processStartedUtc = if ($processInfo -and $processInfo.CreationDate) { ([DateTime]$processInfo.CreationDate).ToUniversalTime() } else { $createdUtc }
@{
  Pid = $devProcess.Id
  StartedUtc = $processStartedUtc.ToString('o')
  FrontendUrl = $actualFrontendUrl
  Mode = $runMode
} | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8

Write-Host "Micro Intent is ready at $actualFrontendUrl (API verified at localhost:3001)."
Write-Host "To stop this instance, run scripts\stop-micro-intent.ps1. Log: $logPath"
Open-App $actualFrontendUrl
