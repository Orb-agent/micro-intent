param([switch]$Public)

$ErrorActionPreference = 'Stop'

$projectId = if ($env:CLOUD_RUN_PROJECT) { $env:CLOUD_RUN_PROJECT } else { 'agentic26zrh-2062' }
$region = if ($env:CLOUD_RUN_REGION) { $env:CLOUD_RUN_REGION } else { 'europe-west6' }
$service = if ($env:CLOUD_RUN_SERVICE) { $env:CLOUD_RUN_SERVICE } else { 'micro-intent' }
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$authMode = if ($Public) { '--allow-unauthenticated' } else { '--no-allow-unauthenticated' }

Push-Location $repositoryRoot
try {
  & gcloud run deploy $service `
    --source $repositoryRoot `
    --project $projectId `
    --region $region `
    --platform managed `
    $authMode `
    --port 8080 `
    --min 0 `
    --max-instances 1 `
    --memory 512Mi `
    --timeout 60 `
    --update-env-vars 'NODE_ENV=production,HOST=0.0.0.0,GEMINI_MODEL=gemini-3.5-flash-lite'

  if ($LASTEXITCODE -ne 0) {
    throw "Cloud Run deployment failed with exit code $LASTEXITCODE."
  }
}
finally {
  Pop-Location
}
