# Full CI Skips Host-Sensitive Upstream Installers

Full CI should keep exercising the normal platform setup path, but it should skip installer surfaces that are known to be host-sensitive in GitHub Actions, such as Flatpak app payloads in Linux containers and AI CLI upstream shell installers in automation. This keeps CI logs meaningful without turning on lightweight `DOTFILES_CI`, which would skip too much of the real install flow.
