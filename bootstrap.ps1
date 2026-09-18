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
$overrideDataFile = $null

function Test-IsCi {
  $ciValue = $env:DOTFILES_CI
  return $ciValue -match "^(1|true|yes)$"
}

function Test-IsAutomation {
  return (Test-IsCi) -or ($env:GITHUB_ACTIONS -match "^(1|true|yes)$") -or ($env:CI -match "^(1|true|yes)$")
}

function Test-UsingCheckedOutSource {
  return (
    $null -ne $scriptDir -and
    (Test-Path (Join-Path $scriptDir ".git")) -and
    (Test-Path (Join-Path $scriptDir ".chezmoiroot"))
  )
}

if (Test-UsingCheckedOutSource) {
  $chezmoiSource = $scriptDir
}

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
  [Console]::Write("`n$esc[A")
  Set-ProgressRegion
  Update-Progress
}

function Stop-Progress {
  if (-not $script:progress.Enabled) { return }
  $script:progress.Enabled = $false
  [Console]::Write("$esc" + "7$esc[$($script:progress.Rows);1H$esc[2K$esc[r$esc" + "8")
}

function Update-Progress {
  if (-not $script:progress.Enabled) { return }

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

function Resolve-WingetPackageIds {
  [CmdletBinding()]
  param(
    [string[]]$PackageIds
  )

  $resolved = @()
  foreach ($pkg in $PackageIds) {
    if ($pkg -notmatch '^(?<family>[A-Za-z0-9]+\.[A-Za-z0-9]+)\.(?<major>[0-9]+)$') {
      $resolved += $pkg
      continue
    }
    $family = $Matches.family
    $major = [int]$Matches.major
    $searchOutput = [string](& winget search --id "$family.$major." --source winget --accept-source-agreements --disable-interactivity 2>$null | Out-String)
    $minors = @([regex]::Matches($searchOutput, [regex]::Escape("$family.$major.") + '(?<minor>[0-9]+)') | ForEach-Object { [int]$_.Groups['minor'].Value } | Sort-Object -Unique)
    if ($minors.Count -eq 0) {
      Write-Warning "Could not resolve the newest $family.$major.x package id from winget; leaving $pkg as is (winget import will report it unavailable)."
      $resolved += $pkg
      continue
    }
    $newest = "$family.$major.$($minors[-1])"
    Write-Host "Resolved $pkg to $newest (newest minor line published on winget)."
    $resolved += $newest
  }
  return ,$resolved
}

function Install-WingetPackages {
  param(
    [string[]]$PackageIds
  )

  if ($PackageIds.Count -eq 0) {
    return
  }

  $manifest = [ordered]@{
    '$schema' = "https://aka.ms/winget-packages.schema.2.0.json"
    Sources = @(
      [ordered]@{
        SourceDetails = [ordered]@{
          Argument = "https://cdn.winget.microsoft.com/cache"
          Identifier = "Microsoft.Winget.Source_8wekyb3d8bbwe"
          Name = "winget"
          Type = "Microsoft.PreIndexed.Package"
        }
        Packages = @(
          $PackageIds | ForEach-Object {
            [ordered]@{
              PackageIdentifier = $_
            }
          }
        )
      }
    )
  }

  $tempWingetManifest = Join-Path ([System.IO.Path]::GetTempPath()) ("dotfiles-winget-{0}.json" -f ([System.Guid]::NewGuid().ToString()))
  try {
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -Path $tempWingetManifest -Encoding utf8
    winget import --import-file $tempWingetManifest --ignore-unavailable --ignore-versions --accept-source-agreements --accept-package-agreements --disable-interactivity
    Assert-LastExitCode "winget import"
  } finally {
    Remove-Item $tempWingetManifest -ErrorAction SilentlyContinue
  }
}

function New-ChezmoiOverrideDataFile {
  param(
    [string]$SelectedProfile
  )

  $featuresTemplate = '{{ (include (joinPath .chezmoi.sourceDir ".." "ansible" "vars" "profiles" (printf "%s.yml" (env "DOTFILES_PROFILE"))) | fromYaml).features | toJson }}'
  $featuresJson = [string]($featuresTemplate | chezmoi execute-template --source $chezmoiSource | Out-String)
  Assert-LastExitCode "chezmoi execute-template (profile features)"
  $features = @($featuresJson | ConvertFrom-Json)
  if ($features.Count -eq 0) {
    throw "Profile '$SelectedProfile' lists no features in ansible/vars/profiles/$SelectedProfile.yml."
  }

  $overrideData = [ordered]@{
    dotfiles_profile = $SelectedProfile
    dotfiles_platform = "windows"
    dotfiles_desktop = "none"
    dotfiles_features = $features
  }
  $path = Join-Path ([System.IO.Path]::GetTempPath()) ("dotfiles-chezmoi-data-{0}.json" -f ([System.Guid]::NewGuid().ToString()))
  [System.IO.File]::WriteAllText($path, ($overrideData | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($false)))
  return $path
}

function Install-Mise {
  if (-not (Get-Command mise -ErrorAction SilentlyContinue)) {
    Write-Host "Installing mise via winget..."
    winget install --id jdx.mise -e --accept-source-agreements --accept-package-agreements --silent --disable-interactivity
    Assert-LastExitCode "winget install jdx.mise" -AllowWingetNoApplicableUpgrade
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
  }
  Add-UserPathEntry -Directory (Join-Path $env:LOCALAPPDATA "mise\shims")
  if (-not (Get-Command mise -ErrorAction SilentlyContinue)) {
    throw "mise was not found on PATH after installing jdx.mise."
  }
}

function Install-MiseTools {
  $env:MISE_YES = "1"
  Write-Host "Installing tools requested in ~/.config/mise/conf.d..."
  mise install
  Assert-LastExitCode "mise install"
  Write-Host "Upgrading mise tools to their latest release..."
  mise upgrade
  Assert-LastExitCode "mise upgrade"
  $missing = [string](& mise ls --missing 2>$null | Out-String)
  if (-not [string]::IsNullOrWhiteSpace($missing)) {
    throw "mise still lists tools as missing after install:`n$missing"
  }
}

function Add-UserPathEntry {
  param(
    [string]$Directory
  )

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
      [Dotfiles.NativeMethods]::SendMessageTimeout([IntPtr]0xffff, 0x001A, [UIntPtr]::Zero, "Environment", 0x0002, 5000, [ref]$result) | Out-Null
    }
  } finally {
    $envKey.Close()
  }

  if (@($env:Path -split ';') -notcontains $Directory) {
    $env:Path = "$env:Path;$Directory"
  }
}

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
$env:DOTFILES_PROFILE = $selectedProfile

Start-Progress -Total 8

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
  chezmoi init
  Assert-LastExitCode "chezmoi init existing checkout"
}
Complete-ProgressStep

Set-ProgressLabel "Symlink support check"
$symlinkProbeTarget = Join-Path ([System.IO.Path]::GetTempPath()) ("chezmoi-symlink-probe-" + [System.IO.Path]::GetRandomFileName())
$symlinkProbeLink = "$symlinkProbeTarget-link"
New-Item -ItemType File -Path $symlinkProbeTarget -Force | Out-Null
$symlinkOk = $false
try {
  New-Item -ItemType SymbolicLink -Path $symlinkProbeLink -Target $symlinkProbeTarget -ErrorAction Stop | Out-Null
  $symlinkOk = $true
} catch {
  cmd /c mklink "$symlinkProbeLink" "$symlinkProbeTarget" > $null 2>&1
  if ($LASTEXITCODE -eq 0) { $symlinkOk = $true }
}
Remove-Item $symlinkProbeLink -Force -ErrorAction SilentlyContinue
Remove-Item $symlinkProbeTarget -Force -ErrorAction SilentlyContinue
if (-not $symlinkOk) {
  throw "This setup creates symlinks (chezmoi mode = ""symlink""), but this Windows session is not allowed to create them. Enable Developer Mode (Settings > System > For developers) or re-run bootstrap from an elevated PowerShell."
}
Complete-ProgressStep

$overrideDataFile = New-ChezmoiOverrideDataFile -SelectedProfile $selectedProfile

Invoke-BestEffort -Phase "chezmoi" -Name "chezmoi apply" -ScriptBlock {
  chezmoi apply --source $chezmoiSource --override-data-file $overrideDataFile --force -v
  Assert-LastExitCode "chezmoi apply"
}
Complete-ProgressStep

Set-ProgressLabel "chezmoi data"
$dataJson = chezmoi data --source $chezmoiSource --override-data-file $overrideDataFile
Assert-LastExitCode "chezmoi data"
$data = $dataJson | ConvertFrom-Json
$profileFeatures = @()
if ($null -ne $data.dotfiles_features) {
    $profileFeatures = @($data.dotfiles_features)
}
Complete-ProgressStep

$pkgs = @()
foreach ($feature in $profileFeatures) {
    $featurePackages = $data.windows_package_sets.$feature.winget
    if ($null -ne $featurePackages) {
        $pkgs += $featurePackages
    }
}
$pkgs = @($pkgs | Select-Object -Unique)
if (-not (Test-IsCi)) {
    $pkgs = Resolve-WingetPackageIds -PackageIds $pkgs
}

if (Test-IsCi) {
    Write-Host "Skipping package installs in lightweight CI mode."
} else {
    Write-Host "Installing packages for $selectedProfile profile..."
    Invoke-BestEffort -Phase "windows_packages" -Name "winget import" -ScriptBlock {
      Install-WingetPackages -PackageIds $pkgs
    }
}
Complete-ProgressStep

$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

if (($profileFeatures -contains "mise") -and (-not (Test-IsCi))) {
    Invoke-BestEffort -Phase "mise" -Name "mise" -ScriptBlock {
        Install-Mise
    }
}
Complete-ProgressStep

if (($profileFeatures -contains "mise") -and (-not (Test-IsCi))) {
    Invoke-BestEffort -Phase "mise" -Name "mise tool lists" -ScriptBlock {
        Install-MiseTools
    }
}
Complete-ProgressStep

if ((-not (Test-IsAutomation)) -and $null -ne $data.ai_clis.clis) {
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
  if ($overrideDataFile) {
    Remove-Item $overrideDataFile -ErrorAction SilentlyContinue
  }
  Stop-Progress
  Write-SetupReport
}
