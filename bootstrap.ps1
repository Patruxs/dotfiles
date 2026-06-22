param(
    [string]$ProfileName = ""
)

$ErrorActionPreference = "Stop"
$repoHttps = "https://github.com/Patruxs/dotfiles.git"
$chezmoiSource = Join-Path $HOME ".local/share/chezmoi"
$profileCacheFile = Join-Path $HOME ".dotfiles_profile"

function Get-Profile {
  if (-not [string]::IsNullOrWhiteSpace($ProfileName)) {
    if ($ProfileName -match "^(personal|work)$") {
      Set-Content -Path $profileCacheFile -Value $ProfileName
      return $ProfileName
    }
    Write-Warning "Provided ProfileName '$ProfileName' is invalid. Falling back to prompt."
  }

  if (Test-Path $profileCacheFile) {
    $savedProfile = (Get-Content $profileCacheFile).Trim()
    $reply = Read-Host "Current profile is $savedProfile. Continue? [Y/n]"
    if ([string]::IsNullOrWhiteSpace($reply) -or $reply -match "^(y|yes)$") {
      return $savedProfile
    }
  }

  while ($true) {
    $reply = Read-Host "Select profile (personal or work)"
    if ($reply -match "^(personal|work)$") {
      Set-Content -Path $profileCacheFile -Value $reply
      return $reply
    }
    Write-Host "Invalid profile. Please enter 'personal' or 'work'."
  }
}

if (-not (Get-Command chezmoi -ErrorAction SilentlyContinue)) {
  winget install --id twpayne.chezmoi -e --accept-source-agreements --accept-package-agreements
  $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
}

if (-not (Test-Path (Join-Path $chezmoiSource ".git"))) {
  chezmoi init $repoHttps
}

$profile = Get-Profile
Write-Host "Using profile: $profile"

chezmoi apply --force -v

Write-Host "Installing packages for $profile profile..."
$dataJson = chezmoi data
$data = $dataJson | ConvertFrom-Json

$pkgs = @()
if ($null -ne $data.packages.common.windows.packages) {
    $pkgs += $data.packages.common.windows.packages
}
if ($null -ne $data.packages.$profile.windows.packages) {
    $pkgs += $data.packages.$profile.windows.packages
}

foreach ($pkg in $pkgs) {
    Write-Host "Installing $pkg via winget..."
    winget install --id $pkg -e --accept-source-agreements --accept-package-agreements --silent
}

if ($null -ne $data.ai_clis.clis) {
    Write-Host "Installing AI CLIs..."
    foreach ($cli in $data.ai_clis.clis.PSObject.Properties) {
        $cmd = $cli.Value.install.windows
        if ($null -ne $cmd) {
            Write-Host "Running AI CLI installer for $($cli.Name)..."
            Invoke-Expression $cmd
        }
    }
}

Write-Host "Bootstrap complete."
