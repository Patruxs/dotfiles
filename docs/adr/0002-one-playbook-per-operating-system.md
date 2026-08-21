# One Playbook Per Operating System

Each operating system has its own standalone Ansible playbook, and bootstrap chooses exactly one playbook after detecting the current OS. This keeps Ubuntu runs from including Fedora, Arch, macOS, or Windows task paths, making both behavior and command output match the current machine.
