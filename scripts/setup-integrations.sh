#!/usr/bin/env bash
# Euro-Office skills - integrations onboarding (gh + Jira).
# Run this in YOUR terminal. Per-person; never commits secrets. Safe to re-run.
# Without any of this, the pipeline still works via manual paste.

info(){ printf '\033[1;34m[setup]\033[0m %s\n' "$*"; }
ok(){   printf '\033[1;32m[ok]\033[0m %s\n'    "$*"; }
warn(){ printf '\033[1;33m[warn]\033[0m %s\n'  "$*"; }

# 1) Detect platform
case "$(uname -s 2>/dev/null || echo unknown)" in
  Linux*)  if grep -qi microsoft /proc/version 2>/dev/null; then PLAT=wsl; else PLAT=linux; fi ;;
  Darwin*) PLAT=macos ;;
  MINGW*|MSYS*|CYGWIN*) PLAT=gitbash ;;
  *) PLAT=unknown ;;
esac
info "Platform detected: $PLAT"

install_hint(){
  case "$PLAT" in
    macos) echo "brew install gh" ;;
    linux|wsl)
      if   command -v apt-get >/dev/null 2>&1; then echo "sudo apt update && sudo apt install -y gh"
      elif command -v dnf     >/dev/null 2>&1; then echo "sudo dnf install -y gh"
      elif command -v pacman  >/dev/null 2>&1; then echo "sudo pacman -S --noconfirm github-cli"
      else echo "see https://github.com/cli/cli#installation"; fi ;;
    gitbash) echo "winget install --id GitHub.cli   (run in PowerShell, or use scripts/setup-integrations.ps1)" ;;
    *) echo "see https://github.com/cli/cli#installation" ;;
  esac
}

# 2) Ensure gh
if command -v gh >/dev/null 2>&1; then
  ok "gh installed: $(gh --version | head -1)"
else
  warn "gh not found. Install with:"
  echo "    $(install_hint)"
  if [ "$PLAT" = "macos" ] || [ "$PLAT" = "linux" ] || [ "$PLAT" = "wsl" ]; then
    printf '\033[1;33m[warn]\033[0m Attempt install now? [y/N] '; read -r ans
    case "$ans" in
      y|Y)
        case "$PLAT" in
          macos) brew install gh || warn "brew install failed - install gh manually." ;;
          linux|wsl)
            if   command -v apt-get >/dev/null 2>&1; then sudo apt update && sudo apt install -y gh || warn "apt install failed."
            elif command -v dnf     >/dev/null 2>&1; then sudo dnf install -y gh || warn "dnf install failed."
            elif command -v pacman  >/dev/null 2>&1; then sudo pacman -S --noconfirm github-cli || warn "pacman install failed."
            fi ;;
        esac ;;
      *) info "Skipping install. Run the command above when ready." ;;
    esac
  fi
fi

# 3) gh auth (interactive - you do it)
if command -v gh >/dev/null 2>&1; then
  if gh auth status >/dev/null 2>&1; then
    ok "gh authenticated."
  else
    warn "gh not authenticated. Starting 'gh auth login' (GitHub.com / HTTPS / account with Euro-Office access)..."
    gh auth login || warn "Auth not completed - run 'gh auth login' yourself later."
  fi
fi

# 4) Jira env (optional)
if [ -n "${JIRA_URL:-}" ] && [ -n "${JIRA_PERSONAL_TOKEN:-}" ]; then
  ok "Jira env present (JIRA_URL is set)."
else
  warn "Jira env not set (optional - only if you use Jira). Add to your shell profile:"
  echo '    export JIRA_URL="https://<your-jira-instance>"'
  echo '    export JIRA_PERSONAL_TOKEN="<your-PAT>"   # never commit this'
  echo "  (bash: ~/.bashrc  -  zsh/macOS: ~/.zshrc  -  Git Bash: ~/.bashrc)"
fi

# 5) Self-check
echo
info "Self-check:"
if command -v gh >/dev/null 2>&1; then gh auth status 2>&1 | sed 's/^/    /'; else echo "    gh: not ready (blueprint will use manual paste)"; fi
echo "    JIRA_URL: ${JIRA_URL:-<unset>}"
echo
ok "Done. If gh is authenticated, /blueprint auto-fetches; otherwise it falls back to manual paste."
