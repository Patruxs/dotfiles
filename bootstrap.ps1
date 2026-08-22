param(
    [string]$ProfileName = "",
    [ValidateSet("", "best_effort", "strict")]
    [string]$SetupMode = ""
)

$ErrorActionPreference = "Stop"
$repoHttps = $env:DOTFILES_REPO
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
$setupAbortReason = $null
$selectedProfile = $null

function Test-IsCi {
  $ciValue = $env:DOTFILES_CI
  return $ciValue -match "^(1|true|yes)$"
}

function Test-UsingCheckedOutSource {
  return (
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

  Set-ProgressLabel $Name
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

# ---------------------------------------------------------------------------
# Progress bar.
#
# On an interactive console that understands VT sequences, the last row is
# reserved for a bar that tracks setup as a whole, one unit per phase; a scroll
# region keeps normal output scrolling above it. Off when output is redirected,
# in lightweight CI mode, or with DOTFILES_PROGRESS=0.
# ---------------------------------------------------------------------------

$progress = @{
  Enabled = $false
  Total = 0
  Done = 0
  Label = ""
  Rows = 0
  Cols = 0
}
$esc = [char]27

function Test-ProgressSupported {
  if ($env:DOTFILES_PROGRESS -match "^(0|false|no)$") { return $false }
  if (Test-IsCi) { return $false }
  if ([Console]::IsOutputRedirected) { return $false }
  return [bool]$Host.UI.SupportsVirtualTerminal
}

function Measure-Progress {
  $script:progress.Rows = [Console]::WindowHeight
  $script:progress.Cols = [Console]::WindowWidth
}

function Set-ProgressRegion {
  # Confine scrolling to every row above the bar.
  [Console]::Write("$esc" + "7$esc[1;$($script:progress.Rows - 1)r$esc" + "8")
}

function Start-Progress {
  param([int]$Total)

  $script:progress.Total = $Total
  $script:progress.Done = 0
  if (-not (Test-ProgressSupported)) { return }
  Measure-Progress
  if ($script:progress.Rows -lt 4 -or $script:progress.Cols -lt 30) { return }
  $script:progress.Enabled = $true
  # Open a fresh line so the bar never covers output already on the last row.
  [Console]::Write("`n$esc[A")
  Set-ProgressRegion
  Update-Progress
}

function Stop-Progress {
  if (-not $script:progress.Enabled) { return }
  $script:progress.Enabled = $false
  # Clear the bar row and give the whole screen back to scrolling.
  [Console]::Write("$esc" + "7$esc[$($script:progress.Rows);1H$esc[2K$esc[r$esc" + "8")
}

function Update-Progress {
  if (-not $script:progress.Enabled) { return }

  # There is no resize signal to catch, so re-measure on every draw and move
  # the region when the window changed.
  $rows = $script:progress.Rows
  $cols = $script:progress.Cols
  Measure-Progress
  if ($rows -ne $script:progress.Rows -or $cols -ne $script:progress.Cols) {
    [Console]::Write("$esc" + "7$esc[r$esc[$($script:progress.Rows);1H$esc[2K$esc" + "8")
    Set-ProgressRegion
  }

  $width = [Math]::Max(10, [int][Math]::Floor($script:progress.Cols / 3))
  $percent = 0
  $filled = 0
  if ($script:progress.Total -gt 0) {
    $percent = [int][Math]::Floor($script:progress.Done * 100 / $script:progress.Total)
    $filled = [int][Math]::Floor($width * $script:progress.Done / $script:progress.Total)
  }
  $bar = ("█" * $filled) + ("░" * ($width - $filled))
  # "bar 100%  " plus one spare column so the line never wraps.
  $maxLabel = [Math]::Max(0, $script:progress.Cols - $width - 10)
  $label = $script:progress.Label
  if ($label.Length -gt $maxLabel) { $label = $label.Substring(0, $maxLabel) }
  $tail = " {0,3}%  {1}" -f $percent, $label
  [Console]::Write("$esc" + "7$esc[$($script:progress.Rows);1H$esc[2K$esc[1m$bar$esc[0m$tail$esc" + "8")
}

function Set-ProgressLabel {
  param([string]$Label)

  $script:progress.Label = $Label
  Update-Progress
}

function Complete-ProgressStep {
  if ($script:progress.Done -lt $script:progress.Total) {
    $script:progress.Done += 1
  }
  Update-Progress
}

function Write-SetupReport {
  # Written from the finally block, so every run leaves a report behind: a
  # best-effort run lists what it skipped, an aborted run says where it stopped.
  $reportPath = Join-Path $HOME ".dotfiles_setup_report.md"
  $profileLabel = if ([string]::IsNullOrWhiteSpace($script:selectedProfile)) { "(not selected)" } else { $script:selectedProfile }
  $result = if ($null -ne $script:setupAbortReason) {
    "Aborted: $($script:setupAbortReason)"
  } elseif ($script:setupFailures.Count -gt 0) {
    "Completed with $($script:setupFailures.Count) skipped failure(s)."
  } else {
    "Completed successfully."
  }

  $lines = @(
    "# Dotfiles setup report",
    "",
    "- Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')",
    "- Profile: ``$profileLabel``",
    "- Platform: ``windows`` (winget)",
    "- Mode: ``$($script:setupMode)``",
    "- Result: $result",
    "",
    $(if ($null -ne $script:setupAbortReason) { "## Errors" } else { "## Errors (skipped, setup continued)" }),
    ""
  )

  if ($script:setupFailures.Count -eq 0) {
    $lines += "No errors were recorded."
    $lines += ""
  } else {
    $index = 0
    foreach ($failure in $script:setupFailures) {
      $index += 1
      $lines += "### $index. [$($failure.Phase)] $($failure.Name)"
      $lines += ""
      $lines += '````text'
      $lines += $(if ([string]::IsNullOrWhiteSpace($failure.Error)) { "(no error output was captured)" } else { $failure.Error.Trim() })
      $lines += '````'
      $lines += ""
    }
  }

  $lines += "## Completed steps"
  $lines += ""
  if ($script:setupSuccesses.Count -eq 0) {
    $lines += "- No setup steps completed."
  } else {
    foreach ($success in $script:setupSuccesses) {
      $lines += "- [$($success.Phase)] $($success.Name)"
    }
  }
  $lines += ""
  $lines += "## Next steps"
  $lines += ""
  $rerunArgs = if ([string]::IsNullOrWhiteSpace($script:selectedProfile)) { "" } else { " -ProfileName $($script:selectedProfile)" }
  $lines += "- Setup is safe to re-run. Fix the cause of any error above, then run ``.\bootstrap.ps1$rerunArgs`` (or the same ``irm ... | iex`` command) again; completed steps are skipped or no-ops."
  $lines += "- Use ``-SetupMode strict`` to stop at the first failure while debugging."

  Set-Content -Path $reportPath -Value ($lines -join "`n") -Encoding utf8

  Write-Host "`n==========================================================="
  Write-Host "Setup result: $result"
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
  if ([string]::IsNullOrWhiteSpace($ProfileName) -and -not [string]::IsNullOrWhiteSpace($env:DOTFILES_PROFILE)) {
    $ProfileName = $env:DOTFILES_PROFILE
  }

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

  # winget import installs missing packages at their latest version
  # (--ignore-versions) and converts already-installed packages to an upgrade
  # by default, so one import keeps every managed package on its latest
  # release. Never add the flag that skips installed packages here.
  $tempWingetManifest = Join-Path ([System.IO.Path]::GetTempPath()) ("dotfiles-winget-{0}.json" -f ([System.Guid]::NewGuid().ToString()))
  try {
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -Path $tempWingetManifest -Encoding utf8
    winget import --import-file $tempWingetManifest --ignore-unavailable --ignore-versions --accept-source-agreements --accept-package-agreements --disable-interactivity
    Assert-LastExitCode "winget import"
  } finally {
    Remove-Item $tempWingetManifest -ErrorAction SilentlyContinue
  }
}

function Install-Llmfit {
  # llmfit is not published on winget, so it is installed straight from its
  # GitHub release: resolve the latest tag at run time, compare it with the
  # installed binary, and download only when they differ. This mirrors the
  # upstream Linux installer, which does the same from a shell script.
  $repo = "AlexsJones/llmfit"
  $installDir = Join-Path $env:LOCALAPPDATA "Programs\llmfit"
  $arch = if ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq [System.Runtime.InteropServices.Architecture]::Arm64) { "aarch64" } else { "x86_64" }

  # Compare against the binary this function manages, not whatever llmfit is
  # first on PATH: an older copy elsewhere (a scoop shim, a manual install)
  # must not make every run re-download the release.
  $managedExe = Join-Path $installDir "llmfit.exe"
  $installedVersion = ""
  if (Test-Path -LiteralPath $managedExe) {
    $versionOutput = [string](& $managedExe --version 2>$null | Out-String)
    if ($versionOutput -match '[0-9]+\.[0-9]+\.[0-9]+') {
      $installedVersion = $Matches[0]
    }
  }

  # The releases/latest redirect carries the tag without touching GitHub's
  # rate-limited API. When GitHub cannot be reached, an existing install is
  # kept rather than reported as a failure, like the Linux installers do.
  $releasesUrl = "https://github.com/$repo/releases/latest"
  $location = ""
  try {
    $request = [System.Net.HttpWebRequest]::Create($releasesUrl)
    $request.AllowAutoRedirect = $false
    $request.UserAgent = "dotfiles-bootstrap"
    $response = $request.GetResponse()
    try {
      $location = [string]$response.Headers["Location"]
    } finally {
      $response.Close()
    }
  } catch {
    if (-not [string]::IsNullOrEmpty($installedVersion)) {
      Write-Warning "Could not reach $releasesUrl to check for a newer llmfit ($($_.Exception.Message)); keeping installed llmfit $installedVersion."
      return
    }
    throw
  }
  if ([string]::IsNullOrWhiteSpace($location) -or $location -notmatch '/tag/(v[0-9]+\.[0-9]+\.[0-9]+)$') {
    throw "Could not resolve the latest llmfit release from $releasesUrl (got '$location')."
  }
  $tag = $Matches[1]
  $latestVersion = $tag.TrimStart('v')

  if ($installedVersion -eq $latestVersion) {
    Write-Host "llmfit $installedVersion is already the latest release."
    return
  }

  $asset = "llmfit-$tag-$arch-pc-windows-msvc.zip"
  $baseUrl = "https://github.com/$repo/releases/download/$tag"
  $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("dotfiles-llmfit-{0}" -f ([System.Guid]::NewGuid().ToString()))
  New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
  try {
    $zipPath = Join-Path $tempDir $asset
    $checksumPath = "$zipPath.sha256"
    Invoke-WebRequest -Uri "$baseUrl/$asset" -OutFile $zipPath -UseBasicParsing
    Invoke-WebRequest -Uri "$baseUrl/$asset.sha256" -OutFile $checksumPath -UseBasicParsing
    $checksumText = [string](Get-Content -Path $checksumPath -Raw)
    if ($checksumText -notmatch '[0-9a-fA-F]{64}') {
      throw "Could not read the llmfit checksum for $asset."
    }
    $expectedHash = $Matches[0].ToLowerInvariant()
    $actualHash = (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $expectedHash) {
      throw "llmfit checksum mismatch for ${asset}: got $actualHash, expected $expectedHash."
    }

    $extractDir = Join-Path $tempDir "extract"
    Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
    $exe = Get-ChildItem -Path $extractDir -Filter "llmfit.exe" -Recurse -File | Select-Object -First 1
    if ($null -eq $exe) {
      throw "llmfit.exe was not found inside $asset."
    }
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    Copy-Item -Path $exe.FullName -Destination $managedExe -Force
  } finally {
    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
  }

  Add-UserPathEntry -Directory $installDir
  Write-Host "Installed llmfit $latestVersion to $installDir."

  $onPath = Get-Command llmfit -ErrorAction SilentlyContinue
  if ($null -ne $onPath -and $onPath.Source -ne $managedExe) {
    Write-Warning "Another llmfit at $($onPath.Source) precedes $managedExe on PATH; remove it (for example 'scoop uninstall llmfit') so the latest release is the one that runs."
  }
}

function Add-UserPathEntry {
  param(
    [string]$Directory
  )

  # Persist the directory on the user PATH for new shells, and add it to this
  # process's PATH so later steps in the same run can call the binary.
  # [Environment]::SetEnvironmentVariable would rewrite the value as REG_SZ
  # with every %VAR% reference expanded, so go through the registry directly
  # and keep the REG_EXPAND_SZ kind, then broadcast the change the way
  # SetEnvironmentVariable does so new windows pick it up.
  $envKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Environment", $true)
  try {
    $rawUserPath = [string]$envKey.GetValue("Path", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    $rawEntries = @($rawUserPath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($rawEntries -notcontains $Directory) {
      $envKey.SetValue("Path", (($rawEntries + $Directory) -join ';'), [Microsoft.Win32.RegistryValueKind]::ExpandString)
      if (-not ("Dotfiles.NativeMethods" -as [type])) {
        Add-Type -Namespace Dotfiles -Name NativeMethods -MemberDefinition @"
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
"@
      }
      $result = [UIntPtr]::Zero
      # HWND_BROADCAST, WM_SETTINGCHANGE, SMTO_ABORTIFHUNG, 5 second timeout.
      [Dotfiles.NativeMethods]::SendMessageTimeout([IntPtr]0xffff, 0x001A, [UIntPtr]::Zero, "Environment", 0x0002, 5000, [ref]$result) | Out-Null
    }
  } finally {
    $envKey.Close()
  }

  if (@($env:Path -split ';') -notcontains $Directory) {
    $env:Path = "$env:Path;$Directory"
  }
}

# Everything below runs inside one try block so that a fatal error (a missing
# prerequisite, a failed clone) is still recorded and reported before the
# script exits; best-effort failures are collected by Invoke-BestEffort.
try {

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
  throw "winget is required but was not found. Install 'App Installer' from the Microsoft Store (or update Windows), then re-run bootstrap."
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

Show-WelcomeScreen
$selectedProfile = Get-Profile
Write-Host "Using profile: $selectedProfile"
# chezmoi init persists this into its config so a later plain `chezmoi apply`
# uses the same profile the bootstrap ran with.
$env:DOTFILES_PROFILE = $selectedProfile

# One unit per phase below: chezmoi init, symlink check, apply, data, winget
# packages, npm tools, Bitwarden CLI, llmfit, AI CLIs. Phases that do not apply to this
# run still count, so the bar always reaches 100%.
Start-Progress -Total 9

Set-ProgressLabel "chezmoi init"
if (Test-UsingCheckedOutSource) {
  Write-Host "Initializing Chezmoi from checked-out source: $chezmoiSource"
  chezmoi init --source $chezmoiSource
  Assert-LastExitCode "chezmoi init checked-out source"
} elseif (-not (Test-Path (Join-Path $chezmoiSource ".git"))) {
  if ([string]::IsNullOrWhiteSpace($repoHttps)) {
    throw "DOTFILES_REPO is required when installing from a downloaded bootstrap script. Set it to your repository URL, for example: https://github.com/USER/dotfiles.git"
  }
  chezmoi init $repoHttps
  Assert-LastExitCode "chezmoi init"
} else {
  Refresh-Repo
}
Complete-ProgressStep

# chezmoi runs in symlink mode, which Windows only allows with Developer Mode
# enabled or an elevated shell. Probe before apply so the failure is actionable.
Set-ProgressLabel "Symlink support check"
$symlinkProbeTarget = Join-Path ([System.IO.Path]::GetTempPath()) ("chezmoi-symlink-probe-" + [System.IO.Path]::GetRandomFileName())
$symlinkProbeLink = "$symlinkProbeTarget-link"
New-Item -ItemType File -Path $symlinkProbeTarget -Force | Out-Null
$symlinkOk = $false
try {
  New-Item -ItemType SymbolicLink -Path $symlinkProbeLink -Target $symlinkProbeTarget -ErrorAction Stop | Out-Null
  $symlinkOk = $true
} catch {
  # Windows PowerShell 5.1 cannot create unprivileged symlinks even with
  # Developer Mode enabled (it never passes
  # SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE); cmd's mklink does pass it,
  # matching what chezmoi itself can do.
  cmd /c mklink "$symlinkProbeLink" "$symlinkProbeTarget" > $null 2>&1
  if ($LASTEXITCODE -eq 0) { $symlinkOk = $true }
}
Remove-Item $symlinkProbeLink -Force -ErrorAction SilentlyContinue
Remove-Item $symlinkProbeTarget -Force -ErrorAction SilentlyContinue
if (-not $symlinkOk) {
  throw "This setup creates symlinks (chezmoi mode = ""symlink""), but this Windows session is not allowed to create them. Enable Developer Mode (Settings > System > For developers) or re-run bootstrap from an elevated PowerShell."
}
Complete-ProgressStep

Invoke-BestEffort -Phase "chezmoi" -Name "chezmoi apply" -ScriptBlock {
  chezmoi apply --source $chezmoiSource --force -v
  Assert-LastExitCode "chezmoi apply"
}
Complete-ProgressStep

Set-ProgressLabel "chezmoi data"
$dataJson = chezmoi data --source $chezmoiSource
Assert-LastExitCode "chezmoi data"
$data = $dataJson | ConvertFrom-Json
Complete-ProgressStep

$pkgs = @()
if ($null -ne $data.packages.common.windows.packages) {
    $pkgs += $data.packages.common.windows.packages
}
if ($null -ne $data.packages.$selectedProfile.windows.packages) {
    $pkgs += $data.packages.$selectedProfile.windows.packages
}
$pkgs = $pkgs | Select-Object -Unique

if (Test-IsCi) {
    Write-Host "Skipping package installs in lightweight CI mode."
} else {
    Write-Host "Installing packages for $selectedProfile profile..."
    Invoke-BestEffort -Phase "windows_packages" -Name "winget import" -ScriptBlock {
      Install-WingetPackages -PackageIds $pkgs -TemplatePath $wingetTemplateFile
    }
}
Complete-ProgressStep

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
Complete-ProgressStep

if ($selectedProfile -eq "personal" -and (-not (Test-IsCi)) -and (Get-Command npm -ErrorAction SilentlyContinue)) {
    Invoke-BestEffort -Phase "bitwarden_cli" -Name "Bitwarden CLI" -ScriptBlock {
        Write-Host "Installing Bitwarden CLI via NPM..."
        npm install -g "@bitwarden/cli@latest"
        Assert-LastExitCode "npm install -g @bitwarden/cli@latest"
    }
}
Complete-ProgressStep

if ($selectedProfile -eq "personal" -and (-not (Test-IsCi))) {
    Invoke-BestEffort -Phase "llmfit" -Name "llmfit" -ScriptBlock {
        Write-Host "Installing or updating llmfit from its latest GitHub release..."
        Install-Llmfit
    }
}
Complete-ProgressStep

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
Complete-ProgressStep

} catch {
  $script:setupAbortReason = if ($null -ne $_.Exception) { $_.Exception.Message } else { [string]$_ }
  Add-SetupFailure -Phase "aborted" -Name "bootstrap" -ErrorRecord $_
  throw
} finally {
  Stop-Progress
  Write-SetupReport
}
