# Changelog

All notable changes to the Canopy compiler will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Performance

#### Planned Optimizations

The following optimizations have been researched and are planned for future releases:

- **Parse Caching** (40-50% expected improvement)
  - Eliminate triple parsing bottleneck
  - Cache AST and imports after first parse

- **Parallel Compilation** (3-5x expected improvement)
  - Dependency-aware task scheduling
  - Multi-core CPU utilization

- **Incremental Compilation** (10-100x for changes)
  - Content-addressable artifact caching
  - Interface stability checking

**Performance Baseline**:
- Small project: ~33ms
- Medium project: ~67ms
- Large project (162 modules): ~35s

### Fixed

- Type system: Number type polymorphism for proper numeric operations
- Type system: Module alias shadowing and qualified name handling
- Type system: Rigid type variable generalization
- Builder: Infinite loop in topological sort
- Builder: Proper compilation error categorization
- Driver: Type error formatting
- Compiler: Boolean negation precedence and type variable loss in annotations

### Added

- `canopy-convert` package for Elm-to-Canopy project conversion
- Coverage command with `--include-deps`, `--show-uncovered`, branch breakdown, merge, and HTML report
- Benchmarking infrastructure

### Changed

- Improved type constraint solving
- Enhanced error reporting

## [0.19.1] - 2025-10-11

### Added

- Initial release with Elm 0.19.1 compatibility
- Multi-package architecture (canopy-core, canopy-builder, canopy-terminal)
- Support for elm.json project files
- Port module support
- Transitive import discovery
- Topological module compilation
- Parallel package loading

### Documentation

- Comprehensive architecture documentation
- Migration guides and status tracking
- FFI system documentation

---

## Version History

- **0.19.1** (2025-10-11): Initial release
- **Unreleased**: Performance optimization planning phase

---

## How to Read This Changelog

- **Added**: New features
- **Changed**: Changes to existing functionality
- **Deprecated**: Features that will be removed
- **Removed**: Features that have been removed
- **Fixed**: Bug fixes
- **Security**: Security fixes
- **Performance**: Performance improvements

Status indicators:
- ✅ Implemented and merged
- 📋 Planned but not yet started
- 🚧 In progress
- ⏸️ Paused/blocked
