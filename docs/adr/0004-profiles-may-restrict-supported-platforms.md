# Profiles May Restrict Supported Platforms

Profiles may declare the platform setups they support, and setup must fail before installation when the current platform is not allowed. This lets a future `server` profile target Ubuntu only without accidentally running on Fedora, Arch, macOS, or Windows.
