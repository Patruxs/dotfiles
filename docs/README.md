# Documentation

How this repository turns a fresh machine into a configured one, and how to change what it does.

The [main README](../README.md) covers installing and using the dotfiles. These documents cover the design underneath.

## Start here

| If you want to... | Read |
| :--- | :--- |
| Understand how a setup run works end to end | [Architecture](architecture.md) |
| Add a tool, app, or platform | [Adding a feature](adding-a-feature.md) |
| Look up a flag, environment variable, or file format | [Reference](reference.md) |
| Know why something is built the way it is | [Why it works this way](architecture.md#why-it-works-this-way) |
| Fork this and make it yours | [Customizing](customizing.md) |
| Open a pull request | [Contributing](../CONTRIBUTING.md) |

## The idea in one paragraph

A **profile** says what a machine is for (`personal`, `work`) by listing **features** it wants (`core_cli`, `docker_desktop`, `flatpak_apps`). A **platform** is one operating system's setup path (`ubuntu`, `fedora`, `arch`, `macos`), and it decides how each feature is actually installed there. Profiles never name packages; platforms never decide purpose. That split is why adding a `server` profile does not mean writing `ubuntu-server`, and why supporting a new distro does not mean editing every profile.

```text
profile (what this machine is for)
   |
   |  selects feature names
   v
feature (a capability, e.g. docker_desktop)
   |
   |  implemented by the current platform
   v
platform (ubuntu | fedora | arch | macos)
   |
   +-- package set   -> direct package entries (apt, dnf, pacman, brew, cask, flatpak)
   +-- feature role  -> procedural install (repos, keys, downloads, services)
```

## Document map

- **[architecture.md](architecture.md)** - the model, the run order, where each responsibility lives, and the reasoning behind each rule.
- **[adding-a-feature.md](adding-a-feature.md)** - the task most contributors come here for, as a checklist.
- **[reference.md](reference.md)** - bootstrap flags, `DOTFILES_*` environment variables, profile and package-set file formats.
- **[customizing.md](customizing.md)** - forking this repository and running your own version of it, step by step.
