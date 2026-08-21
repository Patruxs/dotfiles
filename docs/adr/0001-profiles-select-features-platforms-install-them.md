# Profiles Select Features, Platforms Install Them

Profiles describe the purpose of a machine by selecting features, while platform setup files translate those features into OS-specific packages and installers. This avoids duplicated profiles like `ubuntu-personal` and `ubuntu-server`, and lets a future `server` profile reuse the Ubuntu platform setup without inheriting desktop packages.
