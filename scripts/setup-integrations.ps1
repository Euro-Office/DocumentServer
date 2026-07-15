# Euro-Office skills - integrations onboarding (gh + Jira) for Windows.
# Run in PowerShell. Per-person; never commits secrets. Safe to re-run.
# Without any of this, the pipeline still works via manual paste.

function Info($m){ Write-Host "[setup] $m" -ForegroundColor Cyan }
function Ok($m){   Write-Host "[ok] $m"    -ForegroundColor Green }
function Warn($m){ Write-Host "[warn] $m"  -ForegroundColor Yellow }

Info "Platform: Windows (PowerShell)"

# 1) Ensure gh
if (Get-Command gh -ErrorAction SilentlyContinue) {
  Ok ("gh installed: " + (gh --version)[0])
} else {
  Warn "gh not found."
  $ans = Read-Host "Install GitHub CLI via winget now? [y/N]"
  if ($ans -eq 'y' -or $ans -eq 'Y') {
    winget install --id GitHub.cli --accept-source-agreements --accept-package-agreements
    Info "Reopen the terminal so gh is on PATH, then re-run this script."
    return
  } else {
    Write-Host "    winget install --id GitHub.cli    (or: scoop install gh / choco install gh)"
  }
}

# 2) gh auth (interactive - you do it)
if (Get-Command gh -ErrorAction SilentlyContinue) {
  gh auth status *> $null
  if ($LASTEXITCODE -eq 0) {
    Ok "gh authenticated."
  } else {
    Warn "gh not authenticated. Starting 'gh auth login' (GitHub.com / HTTPS / account with Euro-Office access)..."
    gh auth login
  }
}

# 3) Jira env (optional, user-scope so it persists and Git Bash inherits it)
if ($env:JIRA_URL -and $env:JIRA_PERSONAL_TOKEN) {
  Ok "Jira env present."
} else {
  Warn "Jira env not set (optional - only if you use Jira). Persist as user env vars:"
  Write-Host '    setx JIRA_URL "https://<your-jira-instance>"'
  Write-Host '    setx JIRA_PERSONAL_TOKEN "<your-PAT>"    # never commit this'
  Write-Host "  (reopen the shell afterwards; Git Bash inherits these)"
}

# 4) Self-check
Write-Host ""
Info "Self-check:"
if (Get-Command gh -ErrorAction SilentlyContinue) { gh auth status } else { Write-Host "    gh: not ready (blueprint will use manual paste)" }
if ($env:JIRA_URL) { Write-Host ("    JIRA_URL: " + $env:JIRA_URL) } else { Write-Host "    JIRA_URL: <unset>" }
Write-Host ""
Ok "Done. If gh is authenticated, /blueprint auto-fetches; otherwise it falls back to manual paste."
