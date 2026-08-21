# Features Are Simple Names

Features are simple string names rather than nested configuration objects. This keeps profile files small and makes the first platform/profile split easy to reason about; later choices like nginx versus Caddy can become separate feature names until richer options are clearly needed.
