# Chezmoi Runs For All Profiles With Guarded Templates

All profiles run `chezmoi apply`, including server profiles. Dotfile templates must guard platform-specific or feature-specific content so desktop configuration does not appear on servers and OS-specific files do not leak across platform setups.
