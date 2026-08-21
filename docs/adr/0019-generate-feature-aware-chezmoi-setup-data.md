# Generate Feature-Aware Chezmoi Setup Data

Before `chezmoi apply`, setup records the selected profile, current platform, and selected features in data Chezmoi templates can read. Templates should prefer feature and platform checks over profile-name checks so future profiles like `server` do not require duplicating template branches.
