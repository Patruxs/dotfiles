# Special Installers Are Feature Roles

Installers that need more than a package-set entry are modeled as feature roles selected by feature name. Each feature role owns its platform-specific task files, keeping knowledge about tools like Docker Desktop, Warp, Ghostty, Kiro, or JetBrains Toolbox in one place while still running only the current platform's tasks.
