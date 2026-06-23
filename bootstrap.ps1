param(
    [string]$ProfileName = ""
)

$ErrorActionPreference = "Stop"
$repoHttps = "https://github.com/Patruxs/dotfiles.git"
$chezmoiSource = Join-Path $HOME ".local/share/chezmoi"
$profileCacheFile = Join-Path $HOME ".dotfiles_profile"
$wingetTemplateFile = Join-Path $chezmoiSource "packages/winget.json"

function Show-Banner {
  Write-Host "▓▓▓▓   ▓▓▓  ▓▓▓▓▓ ▓▓▓▓▓ ▓▓▓ ▓     ▓▓▓▓▓  ▓▓▓▓"
  Write-Host "▓   ▓ ▓   ▓   ▓   ▓      ▓  ▓     ▓     ▓"
  Write-Host "▓   ▓ ▓   ▓   ▓   ▓▓▓▓   ▓  ▓     ▓▓▓▓   ▓▓▓"
  Write-Host "▓   ▓ ▓   ▓   ▓   ▓      ▓  ▓     ▓         ▓"
  Write-Host "▓▓▓▓   ▓▓▓    ▓   ▓     ▓▓▓ ▓▓▓▓▓ ▓▓▓▓▓ ▓▓▓▓"
}

function Show-WelcomeScreen {
  if (-not [Console]::IsOutputRedirected -and -not [Console]::IsErrorRedirected) {
    try {
      Clear-Host
    } catch {
      # Ignore non-interactive hosts that do not expose a usable console handle.
    }
  }
  Show-Banner
}

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

function Install-WingetPackages {
  param(
    [string[]]$PackageIds,
    [string]$TemplatePath
  )

  if ($PackageIds.Count -eq 0) {
    return
  }

  if (-not (Test-Path $TemplatePath)) {
    Write-Warning "Winget import template not found at $TemplatePath. Falling back to sequential installs."
    foreach ($pkg in $PackageIds) {
      Write-Host "Installing $pkg via winget..."
      winget install --id $pkg -e --accept-source-agreements --accept-package-agreements --silent
    }
    return
  }

  $manifest = Get-Content $TemplatePath -Raw | ConvertFrom-Json
  if ($null -eq $manifest.Sources -or $manifest.Sources.Count -eq 0) {
    Write-Warning "Winget import template at $TemplatePath is missing Sources data. Falling back to sequential installs."
    foreach ($pkg in $PackageIds) {
      Write-Host "Installing $pkg via winget..."
      winget install --id $pkg -e --accept-source-agreements --accept-package-agreements --silent
    }
    return
  }

  $manifest.Sources[0].Packages = @(
    $PackageIds | ForEach-Object {
      [pscustomobject]@{
        PackageIdentifier = $_
      }
    }
  )

  $tempWingetManifest = Join-Path ([System.IO.Path]::GetTempPath()) ("dotfiles-winget-{0}.json" -f ([System.Guid]::NewGuid().ToString()))
  try {
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -Path $tempWingetManifest -Encoding utf8
    winget import --import-file $tempWingetManifest --ignore-unavailable --no-upgrade --accept-source-agreements --accept-package-agreements
  } finally {
    Remove-Item $tempWingetManifest -ErrorAction SilentlyContinue
  }
}

if (-not (Get-Command chezmoi -ErrorAction SilentlyContinue)) {
  winget install --id twpayne.chezmoi -e --accept-source-agreements --accept-package-agreements
  $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
}

if (-not (Test-Path (Join-Path $chezmoiSource ".git"))) {
  chezmoi init $repoHttps
}

Show-WelcomeScreen
$profile = Get-Profile
Write-Host "Using profile: $profile"

chezmoi apply --force -v

$dataJson = chezmoi data
$data = $dataJson | ConvertFrom-Json

$pkgs = @()
if ($null -ne $data.packages.common.windows.packages) {
    $pkgs += $data.packages.common.windows.packages
}
if ($null -ne $data.packages.$profile.windows.packages) {
    $pkgs += $data.packages.$profile.windows.packages
}
$pkgs = $pkgs | Select-Object -Unique

Write-Host "Installing packages for $profile profile..."
Install-WingetPackages -PackageIds $pkgs -TemplatePath $wingetTemplateFile

$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

if ($null -ne $data.devtools.npm_global_packages -and (Get-Command npm -ErrorAction SilentlyContinue)) {
    Write-Host "Installing global npm development tools..."
    foreach ($pkg in $data.devtools.npm_global_packages) {
        $npmTool = npm list -g $pkg --depth=0 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Installing npm package $pkg..."
            npm install -g $pkg
        }
    }
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
