# Check if profile is personal by inspecting Ansible cache
$cacheFile = "$env:USERPROFILE\.ansible\fact_cache\localhost"
if ((Test-Path $cacheFile) -and (Select-String -Path $cacheFile -Pattern '"dotfiles_profile": "personal"' -Quiet)) {
    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        scoop install llmfit
    }
}

