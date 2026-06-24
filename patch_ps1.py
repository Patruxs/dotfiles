import re

with open('bootstrap.ps1', 'r') as f:
    content = f.read()

# 1. Add setupSuccesses
content = content.replace('$setupFailures = @()', '$setupFailures = @()\n$setupSuccesses = @()')

# 2. Add Add-SetupSuccess function after Add-SetupFailure
success_fn = """
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
"""
content = re.sub(r'(function Add-SetupFailure \{.*?\n\})', r'\1\n' + success_fn, content, flags=re.DOTALL)

# 3. Update Invoke-BestEffort
content = content.replace('    & $ScriptBlock\n  } catch {', '    & $ScriptBlock\n    Add-SetupSuccess -Phase $Phase -Name $Name\n  } catch {')

# 4. Replace Show-SetupFailureSummary with Write-SetupReport
report_fn = """function Write-SetupReport {
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
}"""

content = re.sub(r'function Show-SetupFailureSummary \{.*?\n\}', report_fn, content, flags=re.DOTALL)

# 5. Call Write-SetupReport at the end
content = content.replace('Show-SetupFailureSummary', 'Write-SetupReport')

with open('bootstrap.ps1', 'w') as f:
    f.write(content)
