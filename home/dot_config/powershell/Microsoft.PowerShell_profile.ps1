if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (zoxide init powershell | Out-String) })
}

if (Get-Command mise -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (mise activate pwsh | Out-String) })
}

if (Get-Command starship -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (starship init powershell | Out-String) })
}
