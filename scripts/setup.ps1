# RetailPulse local development setup (Windows PowerShell)

<# 
.SYNOPSIS
  One-stop setup for RetailPulse on Windows using Docker Compose.

.DESCRIPTION
  1. Copies .env.example to .env (if .env does not exist).
  2. Parses .env configuration.
  3. Brings up PostgreSQL via Docker Compose.
  4. Initializes the warehouse schema (roles, security, raw, analytics, audit).
  5. Verifies PostgreSQL health.
  6. Optionally starts Apache Airflow.

.PARAMETER NoPrompt
  Skip interactive prompts (useful in automated execution).
#>
param(
    [switch]$NoPrompt
)

$ErrorActionPreference = "Stop"
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$EnvFile = Join-Path $RepoRoot ".env"
$EnvExample = Join-Path $RepoRoot ".env.example"

Write-Host "== RetailPulse Setup ==" -ForegroundColor Cyan

# 1. Docker availability
Write-Host "Checking Docker..." -ForegroundColor Gray
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Error "Docker is not installed or not on PATH. Please ensure Docker Desktop is running."
}
docker --version | Out-String | Write-Host
docker compose version | Out-String | Write-Host

# 2. Create .env from example if not existing
if (-not (Test-Path $EnvFile)) {
    Write-Host "Creating .env from .env.example..." -ForegroundColor Gray
    Copy-Item $EnvExample $EnvFile
    Write-Host "Initialized .env. Review or edit values if custom credentials are required." -ForegroundColor Yellow
} else {
    Write-Host ".env already exists; preserving existing configuration." -ForegroundColor Gray
}

# Load .env values for PowerShell execution
$DbUser = "retailpulse"
$DbPassword = "changeme_in_env_file"
$DbName = "retailpulse"

if (Test-Path $EnvFile) {
    Get-Content $EnvFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
            $parts = $line.Split("=", 2)
            $key = $parts[0].Trim()
            $val = $parts[1].Trim()
            if ($key -eq "POSTGRES_USER") { $DbUser = $val }
            if ($key -eq "POSTGRES_PASSWORD") { $DbPassword = $val }
            if ($key -eq "POSTGRES_DB") { $DbName = $val }
        }
    }
}

# 3. Start PostgreSQL container
Write-Host "Starting PostgreSQL via Docker Compose..." -ForegroundColor Gray
docker compose -f (Join-Path $RepoRoot "docker-compose.yml") up -d postgres

# 4. Wait for Postgres healthy
Write-Host "Waiting for PostgreSQL to become healthy..." -ForegroundColor Gray
$healthy = $false
for ($i = 0; $i -lt 30; $i++) {
    $status = (docker inspect -f '{{.State.Health.Status}}' retailpulse_postgres 2>$null) -replace "`n",""
    if ($status -eq "healthy") { $healthy = $true; break }
    Start-Sleep -Seconds 2
}
if (-not $healthy) {
    Write-Error "PostgreSQL did not become healthy. Check: docker compose logs postgres"
}
Write-Host "PostgreSQL is healthy." -ForegroundColor Green

# 5. Initialize warehouse schemas, security roles, raw tables, and views
Write-Host "Initializing warehouse schema and security guardrails..." -ForegroundColor Gray
$sqlFiles = @(
    "00_security_and_roles.sql",
    "01_init_schemas.sql",
    "02_raw_tables.sql",
    "04_analytics_model.sql",
    "analytics_views.sql"
)

foreach ($file in $sqlFiles) {
    $filePath = Join-Path (Join-Path $RepoRoot "sql") $file
    if (Test-Path $filePath) {
        Write-Host "Applying sql/$file..." -ForegroundColor Gray
        Get-Content $filePath -Raw | docker exec -i -e PGPASSWORD=$DbPassword retailpulse_postgres psql -U $DbUser -d $DbName
    }
}
Write-Host "Warehouse schema, security roles, and views successfully initialized." -ForegroundColor Green

# 6. Start Airflow
if (-not $NoPrompt) {
    $startAirflow = Read-Host "Start Apache Airflow now? (Y/n)"
    if ($startAirflow -ne "n" -and $startAirflow -ne "N") {
        docker compose -f (Join-Path $RepoRoot "docker-compose.yml") up -d airflow
        Write-Host "Airflow starting at http://localhost:8080 (admin / admin)" -ForegroundColor Green
    }
} else {
    docker compose -f (Join-Path $RepoRoot "docker-compose.yml") up -d airflow
    Write-Host "Airflow started in background at http://localhost:8080" -ForegroundColor Green
}

Write-Host "== Setup complete ==" -ForegroundColor Cyan
Write-Host "Next steps:" -ForegroundColor Gray
Write-Host "  1. Run ingestion: python -m ingestion.ingest"
Write-Host "  2. Run dbt models: dbt build --project-dir dbt --profiles-dir dbt"
Write-Host "  3. Run test suite: pytest"
Write-Host "  4. Access Airflow UI: http://localhost:8080"
