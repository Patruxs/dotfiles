$ErrorActionPreference = "Stop"

$repoHttps = "https://github.com/Patruxs/dotfiles.git"
$repoSsh = "git@github.com:Patruxs/dotfiles.git"
$chezmoiSource = Join-Path $HOME ".local/share/chezmoi"
$wingetFile = Join-Path $chezmoiSource "packages/winget.json"

function Confirm-Step {
  param([string]$Prompt)
  if ($env:DOTFILES_AUTO_INSTALL -eq "1") { return $true }
  $reply = Read-Host "$Prompt [y/N]"
  return $reply -match "^(y|yes)$"
}

if (-not (Get-Command chezmoi -ErrorAction SilentlyContinue)) {
  winget install --id twpayne.chezmoi -e --accept-source-agreements --accept-package-agreements
}

chezmoi init $repoHttps
chezmoi diff

if (-not (Confirm-Step "Apply dotfiles from $repoHttps?")) {
  exit 0
}

chezmoi apply -v

if (Test-Path $wingetFile -and (Confirm-Step "Install curated winget packages?")) {
  winget import -i $wingetFile --ignore-unavailable --accept-source-agreements --accept-package-agreements
}

if (Confirm-Step "Switch chezmoi source remote to SSH?") {
  git -C $chezmoiSource remote set-url origin $repoSsh
}

if (Confirm-Step "Install AI CLIs now?") {
  Write-Host "Codex: powershell -ExecutionPolicy ByPass -c `"irm https://chatgpt.com/codex/install.ps1 | iex`""
  Write-Host "Antigravity: irm https://antigravity.google/cli/install.ps1 | iex"
  Write-Host "Claude: irm https://claude.ai/install.ps1 | iex"
  Write-Host "Droid: irm https://app.factory.ai/cli/windows | iex"
  Write-Host "OpenCode: npm install -g opencode-ai"
}
