# ==============================================================================
# Aris Gateway (9Router) - Windows PowerShell Installer
# Run in PowerShell:
#   irm https://raw.githubusercontent.com/the-abhishek01/9router/master/install.ps1 | iex
# ==============================================================================

[CmdletBinding()]
param (
    [int]$Port = 20128,
    [string]$InstallDir = "$env:USERPROFILE\.9router\gateway",
    [switch]$NoStart
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "   ___         _        ____       __eway " -ForegroundColor Green
Write-Host "  / _ |  ____ (_)___   / __/____ _/ /____ " -ForegroundColor Green
Write-Host " / __ | / __// // -_) _\ \ / _ ``/ __/ -_) " -ForegroundColor Green
Write-Host "/_/ |_|/_/  /_/ \__/ /___/ \_,_/\__/\__/ " -ForegroundColor Green
Write-Host ""
Write-Host "Aris Gateway (9Router) — Obsidian Hyper-Router & Web2API Gateway" -ForegroundColor Cyan
Write-Host "Repository: https://github.com/the-abhishek01/9router" -ForegroundColor DarkGray
Write-Host "------------------------------------------------------------------" -ForegroundColor DarkGray

# 1. Check for Git
$GitCmd = Get-Command git -ErrorAction SilentlyContinue
if (-not $GitCmd) {
    Write-Host "✗ Error: 'git' is required but not installed." -ForegroundColor Red
    Write-Host "You can install it with: winget install --id Git.Git -e" -ForegroundColor Yellow
    exit 1
}

# 2. Check for Node.js
$NodeCmd = Get-Command node -ErrorAction SilentlyContinue
if (-not $NodeCmd) {
    Write-Host "✗ Error: Node.js (v18+) is required but not installed." -ForegroundColor Red
    Write-Host "You can install it with: winget install OpenJS.NodeJS.LTS" -ForegroundColor Yellow
    exit 1
}

$NodeVerStr = (& node -v).Trim().TrimStart('v')
$NodeMajor = [int]($NodeVerStr.Split('.')[0])
if ($NodeMajor -lt 18) {
    Write-Host "✗ Error: Node.js version 18+ is required. Found: v$NodeVerStr" -ForegroundColor Red
    Write-Host "Please upgrade Node.js: winget install OpenJS.NodeJS.LTS" -ForegroundColor Yellow
    exit 1
}
Write-Host "✓ Node.js Runtime: v$NodeVerStr" -ForegroundColor Green

# 3. Check for npm
$NpmCmd = Get-Command npm -ErrorAction SilentlyContinue
if (-not $NpmCmd) {
    Write-Host "✗ Error: 'npm' is required but not found in PATH." -ForegroundColor Red
    exit 1
}

# 4. Clone or Update Repository
$RepoUrl = "https://github.com/the-abhishek01/9router.git"

if (Test-Path "package.json") {
    $PkgContent = Get-Content "package.json" -Raw
    if ($PkgContent -match '"aris-app"') {
        $InstallDir = (Get-Location).Path
        Write-Host "→ Running inside existing repository: $InstallDir" -ForegroundColor Cyan
    }
}

if (-not (Test-Path (Join-Path $InstallDir "package.json"))) {
    Write-Host "→ Cloning 9Router into: $InstallDir" -ForegroundColor Cyan
    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }
    & git clone --depth=1 $RepoUrl $InstallDir
} else {
    Write-Host "→ Updating repository in: $InstallDir" -ForegroundColor Cyan
    Push-Location $InstallDir
    & git fetch --depth=1 origin master 2>$null
    & git reset --hard origin/master 2>$null
    Pop-Location
}

Push-Location $InstallDir

# 5. Install Dependencies
Write-Host "→ Installing project dependencies..." -ForegroundColor Cyan
& npm install --no-audit --no-fund --loglevel=error

# 6. Verify CLI standalone build exists
$ServerFile = Join-Path $InstallDir "cli\app\custom-server.js"
if (-not (Test-Path $ServerFile)) {
    Write-Host "→ Compiling standalone Aris CLI distribution..." -ForegroundColor Cyan
    & node cli\scripts\build-cli.js
}

# Ensure Next.js standalone runtime compatibility
& node -e "try { require('./cli/hooks/nextRuntime').ensureNextRuntime(); } catch {}" 2>$null

# 7. Create Global CLI Launcher Commands
$BinDir = "$env:USERPROFILE\.local\bin"
if (-not (Test-Path $BinDir)) {
    New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
}

$ArisCmdContent = "@echo off`r`nnode `"$InstallDir\cli\cli.js`" %*"
Set-Content -Path "$BinDir\aris.cmd" -Value $ArisCmdContent -Encoding ASCII
Set-Content -Path "$BinDir\9router.cmd" -Value $ArisCmdContent -Encoding ASCII

# Add to user PATH if not present
$UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($UserPath -notlike "*$BinDir*") {
    [Environment]::SetEnvironmentVariable("Path", "$UserPath;$BinDir", "User")
    $env:Path = "$env:Path;$BinDir"
    Write-Host "✓ Added $BinDir to User PATH environment variable." -ForegroundColor Green
}

Pop-Location

Write-Host ""
Write-Host "==================================================================" -ForegroundColor Green
Write-Host "   ⚡ Aris Gateway (9Router) is Ready!" -ForegroundColor Green
Write-Host "==================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Dashboard URL:      http://localhost:$Port/dashboard" -ForegroundColor Cyan
Write-Host "  OpenAI Endpoint:    http://localhost:$Port/v1" -ForegroundColor Cyan
Write-Host "  Installed To:       $InstallDir" -ForegroundColor DarkGray
Write-Host "  Global Commands:    aris or 9router" -ForegroundColor Green
Write-Host ""

# 8. Start Gateway
if (-not $NoStart) {
    Write-Host "→ Launching Aris Gateway on port $Port..." -ForegroundColor Cyan
    $env:PORT = "$Port"
    & node "$InstallDir\cli\cli.js" --port $Port
}
