<#
.SYNOPSIS
  Builds (optionally) and runs mybestsim-integration-api on a local Mule Community runtime.
.DESCRIPTION
  - Reads ../.env (see .env.example); relative directories are resolved against the repository root.
  - Downloads Mule CE (-MuleVersion, default 4.7.0) into .tools/ on first use when MULE_HOME is not set.
  - Copies the application jar into <MULE_HOME>/apps and starts the runtime in the foreground.
  Nothing is imported at startup: the import runs only on the scheduler (if enabled) or POST /api/v1/imports.
.EXAMPLE
  ./scripts/run-mule.ps1 -Build
#>
param(
    [switch]$Build,
    [string]$MuleEnv = "dev",
    [string]$MuleVersion = "4.7.0"
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

# --- load .env -------------------------------------------------------------
$envFile = Join-Path $root ".env"
if (-not (Test-Path $envFile)) { throw ".env not found: copy .env.example to .env first." }
Get-Content $envFile | ForEach-Object {
    if ($_ -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$' -and -not $_.TrimStart().StartsWith("#")) {
        [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], "Process")
    }
}
foreach ($v in "MYBESTSIM_SOURCE_DIR", "MYBESTSIM_PROCESSED_DIR", "MYBESTSIM_REJECTED_DIR") {
    $value = [Environment]::GetEnvironmentVariable($v, "Process")
    if (-not [IO.Path]::IsPathRooted($value)) { $value = [IO.Path]::GetFullPath((Join-Path $root ($value -replace '^\.\./', ''))) }
    New-Item -ItemType Directory -Force $value | Out-Null
    [Environment]::SetEnvironmentVariable($v, $value, "Process")
    Write-Host "$v = $value"
}

# --- Mule runtime ------------------------------------------------------------
$muleHome = $env:MULE_HOME
if (-not $muleHome) {
    $muleHome = Join-Path $root ".tools/mule-standalone-$MuleVersion"
    if (-not (Test-Path $muleHome)) {
        New-Item -ItemType Directory -Force (Join-Path $root ".tools") | Out-Null
        $zip = Join-Path $root ".tools/mule-$MuleVersion.zip"
        Invoke-WebRequest "https://repository.mulesoft.org/releases/org/mule/distributions/mule-standalone/$MuleVersion/mule-standalone-$MuleVersion.zip" -OutFile $zip
        Expand-Archive $zip -DestinationPath (Join-Path $root ".tools")
    }
}

if ($MuleVersion -like "4.7.*") { python (Join-Path $root "scripts/patch_mule47_launcher.py") $muleHome }  # quote module path (spaces in install path)

# --- build + deploy ----------------------------------------------------------
$project = Join-Path $root "mule/mybestsim-integration-api-test"
if ($Build -or -not (Test-Path (Join-Path $project "target/mybestsim-integration-api-test-1.0.0-SNAPSHOT-mule-application.jar"))) {
    Push-Location $project; mvn -B -q -DskipTests package; if ($LASTEXITCODE) { throw "Maven build failed" }; Pop-Location
}
$apps = Join-Path $muleHome "apps"
Get-ChildItem $apps -Directory -ErrorAction SilentlyContinue | Where-Object Name -like "mybestsim-integration-api*" | Remove-Item -Recurse -Force
Get-ChildItem $apps -Filter "mybestsim-integration-api*" -File -ErrorAction SilentlyContinue | Remove-Item -Force
Copy-Item (Join-Path $project "target/mybestsim-integration-api-test-1.0.0-SNAPSHOT-mule-application.jar") (Join-Path $apps "mybestsim-integration-api.jar")

Write-Host "Starting Mule ($MuleEnv) - Ctrl+C to stop"
& (Join-Path $muleHome "bin/mule.bat") "-M-Dmule.env=$MuleEnv"
