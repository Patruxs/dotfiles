# Platform Playbooks Use A Shared Common Flow

Each supported Unix/macOS platform has its own standalone playbook entrypoint, but those playbooks may set platform-specific facts and package data before invoking a shared common flow. This avoids loading the wrong platform while also avoiding duplicated orchestration logic across Ubuntu, Fedora, Arch, and macOS.
