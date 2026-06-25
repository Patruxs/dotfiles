param(
    [string]$ProfileName = "",
    [ValidateSet("", "best_effort", "strict")]
    [string]$SetupMode = ""
)

$ErrorActionPreference = "Stop"
$repoHttps = "https://github.com/Patruxs/dotfiles.git"
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } elseif ($PSCommandPath) { Split-Path -Parent $PSCommandPath } else { $null }
$chezmoiSource = Join-Path $HOME ".local/share/chezmoi"
$profileCacheFile = Join-Path $HOME ".dotfiles_profile"
$setupMode = if (-not [string]::IsNullOrWhiteSpace($SetupMode)) {
  $SetupMode
} elseif ($env:DOTFILES_SETUP_MODE -match "^(best_effort|strict)$") {
  $env:DOTFILES_SETUP_MODE
} else {
  "best_effort"
}
$setupFailures = @()
$setupSuccesses = @()

function Test-IsCi {
  $ciValue = $env:DOTFILES_CI
  return $ciValue -match "^(1|true|yes)$"
}

function Test-IsAutomation {
  $ciValue = if ($env:GITHUB_ACTIONS) { $env:GITHUB_ACTIONS } elseif ($env:CI) { $env:CI } else { $env:DOTFILES_CI }
  return $ciValue -match "^(1|true|yes)$"
}

function Test-UsingCheckedOutSource {
  return (
    (Test-IsAutomation) -and
    $null -ne $scriptDir -and
    (Test-Path (Join-Path $scriptDir ".git")) -and
    (Test-Path (Join-Path $scriptDir "packages/winget.json"))
  )
}

if (Test-UsingCheckedOutSource) {
  $chezmoiSource = $scriptDir
}

$wingetTemplateFile = Join-Path $chezmoiSource "packages/winget.json"

function Assert-LastExitCode {
  param(
    [string]$CommandName,
    [switch]$AllowWingetNoApplicableUpgrade
  )

  if ($LASTEXITCODE -eq 0) {
    return
  }

  # winget reports 0x8A15002B through PowerShell's $LASTEXITCODE as a signed Int32.
  if ($AllowWingetNoApplicableUpgrade -and $LASTEXITCODE -eq -1978335189) {
    Write-Host "$CommandName reported no available upgrade. Continuing."
    return
  }

  throw "$CommandName failed with exit code $LASTEXITCODE."
}

function Add-SetupFailure {
  param(
    [string]$Phase,
    [string]$Name,
    [object]$ErrorRecord
  )

  $message = if ($null -ne $ErrorRecord -and $null -ne $ErrorRecord.Exception) {
    $ErrorRecord.Exception.Message
  } elseif ($null -ne $ErrorRecord) {
    [string]$ErrorRecord
  } else {
    "Unknown error"
  }

  $script:setupFailures += [pscustomobject]@{
    Phase = $Phase
    Name = $Name
    Error = $message
  }
}

function Add-SetupSuccess {
  param(
    [string]$Phase,
    [string]$Name
  )

  $script:setupSuccesses += [pscustomobject]@{
    Phase = $Phase
    Name = $Name
  }
}


function Invoke-BestEffort {
  param(
    [string]$Phase,
    [string]$Name,
    [scriptblock]$ScriptBlock
  )

  try {
    & $ScriptBlock
    Add-SetupSuccess -Phase $Phase -Name $Name
  } catch {
    if ($script:setupMode -eq "strict") {
      throw
    }

    Add-SetupFailure -Phase $Phase -Name $Name -ErrorRecord $_
    Write-Warning "$Phase '$Name' failed. Continuing setup."
  }
}

function Write-SetupReport {
  $reportPath = Join-Path $HOME ".dotfiles_setup_report.md"
  $content = "# Setup Outcome Breakdown`n`n"
  
  $content += "## What was Successfully Installed/Configured`n"
  if ($script:setupSuccesses.Count -eq 0) {
    $content += "No setup phases completed successfully.`n"
  } else {
    foreach ($success in $script:setupSuccesses) {
      $content += "- [$($success.Phase)] $($success.Name)`n"
    }
  }

  $content += "`n## What Failed`n"
  if ($script:setupFailures.Count -eq 0) {
    $content += "No errors were recorded.`n"
  } else {
    foreach ($failure in $script:setupFailures) {
      $content += "- [$($failure.Phase)] $($failure.Name): $($failure.Error)`n"
    }
  }
  
  Set-Content -Path $reportPath -Value $content -Encoding utf8
  
  Write-Host "`n==========================================================="
  Write-Host "Setup finished (or aborted). A full report has been saved."
  Write-Host "Read your setup outcome summary at: $reportPath"
  Write-Host "==========================================================="
}

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

function Refresh-Repo {
  if (Test-UsingCheckedOutSource) {
    Write-Host "Using checked-out dotfiles repo without refreshing it."
    return
  }

  if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    return
  }

  Push-Location $chezmoiSource
  try {
    git diff --quiet --ignore-submodules HEAD -- 2>$null
    $worktreeClean = ($LASTEXITCODE -eq 0)
    git diff --quiet --ignore-submodules --cached -- 2>$null
    $indexClean = ($LASTEXITCODE -eq 0)

    if ($worktreeClean -and $indexClean) {
      Write-Host "Refreshing dotfiles repo..."
      git pull --ff-only --quiet
      if ($LASTEXITCODE -ne 0) {
        Write-Warning "Could not fast-forward the existing dotfiles checkout. Continuing with the local copy."
      }
    } else {
      Write-Host "Skipping dotfiles repo refresh because the local checkout has uncommitted changes."
    }
  } finally {
    Pop-Location
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
      Invoke-BestEffort -Phase "windows_package" -Name $pkg -ScriptBlock {
        Write-Host "Installing or updating $pkg via winget..."
        winget install --id $pkg -e --accept-source-agreements --accept-package-agreements --silent --disable-interactivity
        Assert-LastExitCode "winget install $pkg"
      }
    }
    return
  }

  $manifest = Get-Content $TemplatePath -Raw | ConvertFrom-Json
  if ($null -eq $manifest.Sources -or $manifest.Sources.Count -eq 0) {
    Write-Warning "Winget import template at $TemplatePath is missing Sources data. Falling back to sequential installs."
    foreach ($pkg in $PackageIds) {
      Invoke-BestEffort -Phase "windows_package" -Name $pkg -ScriptBlock {
        Write-Host "Installing or updating $pkg via winget..."
        winget install --id $pkg -e --accept-source-agreements --accept-package-agreements --silent --disable-interactivity
        Assert-LastExitCode "winget install $pkg"
      }
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
    winget import --import-file $tempWingetManifest --ignore-unavailable --ignore-versions --accept-source-agreements --accept-package-agreements --disable-interactivity
    Assert-LastExitCode "winget import"
  } finally {
    Remove-Item $tempWingetManifest -ErrorAction SilentlyContinue
  }
}

if (-not (Get-Command chezmoi -ErrorAction SilentlyContinue)) {
  winget install --id twpayne.chezmoi -e --accept-source-agreements --accept-package-agreements
  Assert-LastExitCode "winget install twpayne.chezmoi" -AllowWingetNoApplicableUpgrade
  $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
} elseif (Test-IsCi) {
  Write-Host "Skipping chezmoi self-upgrade in lightweight CI mode."
} else {
  try {
    chezmoi upgrade
    Assert-LastExitCode "chezmoi upgrade"
  } catch {
    Write-Warning "Could not self-upgrade chezmoi. Continuing with the current version."
  }
}

if (-not (Test-Path (Join-Path $chezmoiSource ".git"))) {
  chezmoi init $repoHttps
  Assert-LastExitCode "chezmoi init"
} else {
  Refresh-Repo
}

Show-WelcomeScreen
$profile = Get-Profile
Write-Host "Using profile: $profile"

chezmoi apply --source $chezmoiSource --force -v
Assert-LastExitCode "chezmoi apply"

$dataJson = chezmoi data --source $chezmoiSource
Assert-LastExitCode "chezmoi data"
$data = $dataJson | ConvertFrom-Json

$pkgs = @()
if ($null -ne $data.packages.common.windows.packages) {
    $pkgs += $data.packages.common.windows.packages
}
if ($null -ne $data.packages.$profile.windows.packages) {
    $pkgs += $data.packages.$profile.windows.packages
}
$pkgs = $pkgs | Select-Object -Unique

if (Test-IsCi) {
    Write-Host "Skipping package installs in lightweight CI mode."
} else {
    Write-Host "Installing packages for $profile profile..."
    Invoke-BestEffort -Phase "windows_packages" -Name "winget import" -ScriptBlock {
      Install-WingetPackages -PackageIds $pkgs -TemplatePath $wingetTemplateFile
    }
}

$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

if ((-not (Test-IsCi)) -and $null -ne $data.devtools.npm_global_packages -and (Get-Command npm -ErrorAction SilentlyContinue)) {
    Write-Host "Installing or updating global npm development tools..."
    foreach ($pkg in $data.devtools.npm_global_packages) {
        Invoke-BestEffort -Phase "npm_global" -Name $pkg -ScriptBlock {
            Write-Host "Installing or updating npm package $pkg..."
            npm install -g "$pkg@latest"
            Assert-LastExitCode "npm install -g $pkg@latest"
        }
    }
}

if ($profile -eq "personal" -and (-not (Test-IsCi)) -and (Get-Command npm -ErrorAction SilentlyContinue)) {
    Invoke-BestEffort -Phase "bitwarden_cli" -Name "Bitwarden CLI" -ScriptBlock {
        Write-Host "Installing Bitwarden CLI via NPM..."
        npm install -g "@bitwarden/cli@latest"
        Assert-LastExitCode "npm install -g @bitwarden/cli@latest"
    }
}

if ((-not (Test-IsCi)) -and $null -ne $data.ai_clis.clis) {
    Write-Host "Installing AI CLIs..."
    foreach ($cli in $data.ai_clis.clis.PSObject.Properties) {
        $cmd = $cli.Value.install.windows
        if ($null -ne $cmd) {
            Invoke-BestEffort -Phase "ai_cli" -Name $cli.Name -ScriptBlock {
                Write-Host "Running AI CLI installer for $($cli.Name)..."
                Invoke-Expression $cmd
                Assert-LastExitCode "$($cli.Name) installer"
            }
        }
    }
}

Write-SetupReport
