# Package Management

Canopy has a built-in package manager that handles dependency resolution, installation, and versioning.

## Project Configuration

Every Canopy project has a `canopy.json` file at its root.

### Application Projects

```json
{
    "type": "application",
    "source-directories": ["src"],
    "canopy-version": "0.19.1",
    "dependencies": {
        "direct": {
            "canopy/browser": "1.0.2",
            "canopy/core": "1.0.5",
            "canopy/html": "1.0.0",
            "canopy/http": "2.0.0",
            "canopy/json": "1.1.3"
        },
        "indirect": {
            "canopy/bytes": "1.0.8",
            "canopy/time": "1.0.0",
            "canopy/url": "1.0.0",
            "canopy/virtual-dom": "1.0.3"
        }
    },
    "test-dependencies": {
        "direct": {},
        "indirect": {}
    }
}
```

### Package Projects

```json
{
    "type": "package",
    "name": "author/package-name",
    "summary": "A short description of what this package does",
    "license": "MIT",
    "version": "1.0.0",
    "exposed-modules": [
        "MyModule",
        "MyModule.Sub"
    ],
    "canopy-version": "0.19.0 <= v < 0.20.0",
    "dependencies": {
        "canopy/core": "1.0.0 <= v < 2.0.0"
    },
    "test-dependencies": {}
}
```

## Installing Packages

```bash
# Install a package
canopy install canopy/http

# Install a specific version
canopy install canopy/http@2.0.0
```

When you install a package, Canopy:

1. Resolves all transitive dependencies
2. Checks for version conflicts
3. Downloads and caches packages
4. Updates your `canopy.json`
5. Generates `canopy.lock` for reproducible builds

## Version Constraints

For packages, dependencies use version ranges:

| Constraint | Meaning |
|-----------|---------|
| `1.0.0 <= v < 2.0.0` | Any 1.x version |
| `1.2.0 <= v < 1.3.0` | Any 1.2.x version |
| `1.0.0 <= v < 1.0.1` | Exactly 1.0.0 |

Canopy follows semantic versioning. The compiler enforces API compatibility:

- **Patch** (1.0.0 -> 1.0.1): Bug fixes, no API changes
- **Minor** (1.0.0 -> 1.1.0): Additions only, no breaking changes
- **Major** (1.0.0 -> 2.0.0): Breaking changes allowed

## Capabilities

Applications can declare security capabilities:

```json
{
    "capabilities": {
        "allow": ["network", "geolocation"],
        "deny": ["camera"]
    }
}
```

Or as a simple list (allow-only):

```json
{
    "capabilities": ["network", "geolocation"]
}
```

See the [Capability Security](./capability-security.md) guide for details.

## Lock Files

`canopy.lock` records the exact versions resolved for all dependencies. Commit this file to version control for reproducible builds.

## Removing Packages

Edit `canopy.json` directly to remove a dependency from the `direct` section, then run:

```bash
canopy install
```

This re-resolves dependencies and cleans up unused indirect dependencies.

## Publishing Packages

```bash
# Check your package is ready
canopy diff

# Bump the version based on API changes
canopy bump

# Publish to the registry
canopy publish
```

The compiler automatically detects whether your changes are patch, minor, or major based on API differences.
