# Quick Reference: Package Namespace Migration Strategies

## TL;DR - Recommended Approach for Canopy

**Hybrid Strategy**: Compiler Aliasing + Wrapper Packages + Automated Tooling + 2-3 Year Timeline

### Implementation Priority

1. **Compiler-level aliasing** (like Swift) - transparent to users
2. **Automated `canopy migrate` tool** (like Dropbox) - easy migration path
3. **Wrapper packages** (like Rust/Haskell) - perfect backwards compatibility
4. **Long timeline** (2-3 years) - allow ecosystem to adapt

---

## Quick Comparison

| Approach | Compatibility | Implementation | Best For |
|----------|--------------|----------------|----------|
| **Compiler Aliasing** | Excellent | Hard | Controlled ecosystems |
| **Wrapper Packages** | Excellent | Medium | Gradual migration |
| **Deprecation Only** | Poor | Easy | Breaking changes OK |
| **Migration Tool** | Good | Medium | User-driven migration |

---

## Three Best Examples to Copy

### 1. Swift Module Aliasing (10/10)
**What They Did**: Compiler-level module name mapping via build system
**Why It Works**: Completely transparent to users, zero breaking changes
**Copy This**: Implement compiler-level `elm/*` → `canopy/*` rewriting

### 2. Haskell Cabal Re-exports (9/10)
**What They Did**: Module re-export feature for package splits
**Why It Works**: Perfect backwards compatibility, declarative
**Copy This**: Create elm/* shim packages that re-export canopy/* modules

### 3. Dropbox Underscore→Lodash (10/10)
**What They Did**: Automated codemods + phased rollout + team organization
**Why It Works**: Only 1 bug post-launch despite 100+ engineers
**Copy This**: Build `canopy migrate` tool with dry-run, backup, rollback

---

## Timeline Template

### Months 1-3: Announcement
- Public announcement across all channels
- Draft migration guide
- Community feedback

### Months 4-6: Tools Development
- Implement compiler aliasing
- Build `canopy migrate` command
- Beta testing

### Months 7-18: Active Migration
- Escalating deprecation warnings
- Community support
- Progress tracking

### Months 19-24: Wrapper Packages
- Publish elm/* shims
- Implement re-export mechanism
- Indefinite maintenance commitment

### Year 3+: Optional Strictness
- Compiler flag for strict mode
- Never remove automatic aliasing

---

## Common Mistakes to Avoid

1. ❌ Unpublishing without notice (left-pad)
2. ❌ No automated tooling (doesn't scale)
3. ❌ Too short timeline (ecosystem needs 2-3 years)
4. ❌ Breaking backwards compatibility (always provide shims)
5. ❌ Poor communication (multi-channel required)
6. ❌ All-at-once migration (phase it)
7. ❌ Forgetting abandoned projects (maintain wrappers indefinitely)

---

## Code Snippets

### Compiler Aliasing (Conceptual)

```haskell
-- builder/src/Deps/Solver.hs
resolvePackage :: PackageName -> CompilerConfig -> PackageName
resolvePackage pkg config
  | isElmNamespace pkg && config ^. enableLegacyElmCompat =
      rewriteToCanopyNamespace pkg
  | otherwise = pkg

rewriteToCanopyNamespace :: PackageName -> PackageName
rewriteToCanopyNamespace (Package "elm" project) =
  Package "canopy" project
rewriteToCanopyNamespace pkg = pkg
```

### Wrapper Package (elm/core → canopy/core)

```json
{
  "type": "package",
  "name": "elm/core",
  "version": "1.0.0",
  "deprecated": {
    "message": "Use canopy/core instead. Install: canopy install canopy/core",
    "replacement": "canopy/core"
  },
  "dependencies": {
    "canopy/core": "1.0.0 <= v < 2.0.0"
  },
  "reexported-modules": {
    "canopy/core": ["Basics", "List", "Maybe", "Result", "String", "Char", "Tuple", "Debug", "Platform"]
  }
}
```

### Migration Tool Command

```bash
# Dry run
canopy migrate --dry-run

# Create backup and migrate
canopy migrate --backup

# Migrate specific packages only
canopy migrate --packages elm/core,elm/json

# Report only (no changes)
canopy migrate --report
```

---

## Key Statistics

- **Rust ecosystem**: 2-3 years for natural crate migration
- **Python 2→3**: Took 5+ years for full ecosystem adoption
- **Dropbox migration**: 6 months with only 1 bug post-launch
- **NPM recommendation**: 6-12 month deprecation period
- **Consensus timeline**: 2-3 years for breaking namespace changes

---

## Most Relevant References

1. **Swift SE-0339**: https://github.com/swiftlang/swift-evolution/blob/main/proposals/0339-module-aliasing-for-disambiguation.md
2. **Haskell Cabal Re-exports**: https://cabal.readthedocs.io/en/3.6/cabal-package.html
3. **Dropbox Case Study**: https://dropbox.tech/frontend/migrating-from-underscore-to-lodash
4. **Package Deprecation Best Practices**: https://json-server.dev/deprecation-package-policy/

---

## Decision Framework

### Should You Implement Compiler Aliasing?
✅ YES if: You control the compiler, want zero breaking changes
❌ NO if: Third-party tools needed, ecosystem too distributed

### Should You Maintain Wrapper Packages?
✅ YES if: Backwards compatibility critical, gradual migration desired
❌ NO if: Breaking changes acceptable, clean break preferred

### Should You Build Migration Tooling?
✅ ALWAYS if: Ecosystem has more than 100 users
❌ NEVER SKIP if: Migration affects user code

### What Timeline Should You Choose?
- **< 6 months**: Too short, ecosystem can't adapt
- **6-12 months**: OK for deprecation-only approach
- **2-3 years**: Recommended for namespace changes
- **5+ years**: Too long, maintains technical debt

---

## Success Metrics

Track these to measure migration progress:

1. **Adoption Rate**: % of packages using canopy/* namespace
2. **Active Projects**: % of recently-updated projects migrated
3. **Compiler Warnings**: Trend over time (should decrease)
4. **Community Feedback**: Sentiment analysis
5. **Support Requests**: Volume and type of migration issues

---

**Last Updated**: 2025-10-27
**See Full Report**: `/home/quinten/fh/canopy/.hive-mind/research/namespace-migration-strategies.md`
