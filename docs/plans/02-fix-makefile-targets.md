# Plan 02 — Fix Broken Makefile Targets

**Priority:** Tier 0 (Blocker)
**Effort:** 1 hour
**Risk:** None
**Files:** `Makefile`

---

## Problem

The `lint`, `format`, `fix-lint`, and `fix-lint-folder` targets in the Makefile reference directories that no longer exist: `compiler/`, `builder/`, `terminal/`, `test/`. The source code now lives under `packages/canopy-core/src/`, `packages/canopy-builder/src/`, `packages/canopy-terminal/src/`, `packages/canopy-terminal/impl/`, and `test/`.

These targets silently succeed (find no files) giving false confidence that code passes lint/format checks.

## Evidence

```makefile
# Current (broken):
lint:
    @hlint compiler builder terminal test
    @ormolu --mode=check $(shell find compiler builder terminal test -name '*.hs')

format:
    @ormolu -i $(shell find builder compiler terminal test -name '*.hs')
```

The directories `compiler/`, `builder/`, `terminal/` do not exist at the repo root. The `find` command returns nothing.

## Implementation

### Step 1: Update directory references

Replace all old directory references with the current package layout:

```makefile
# Source directories
SRC_DIRS := packages/canopy-core/src \
            packages/canopy-builder/src \
            packages/canopy-terminal/src \
            packages/canopy-terminal/impl \
            packages/canopy-driver/src \
            packages/canopy-query/src \
            test

# Find all Haskell source files
HS_FILES := $(shell find $(SRC_DIRS) -name '*.hs' -not -path '*/dist-*' -not -path '*/.stack-work/*')
```

### Step 2: Update lint target

```makefile
lint:
	@echo "Running hlint..."
	@hlint $(SRC_DIRS)
	@echo "Running ormolu check..."
	@ormolu --mode=check $(HS_FILES)
	@echo "Lint passed."
```

### Step 3: Update format target

```makefile
format:
	@echo "Formatting with ormolu..."
	@ormolu -i $(HS_FILES)
	@echo "Formatted $(words $(HS_FILES)) files."
```

### Step 4: Update fix-lint and fix-lint-folder

```makefile
fix-lint:
	@hlint --refactor --refactor-options="--inplace" $(SRC_DIRS)
	@ormolu -i $(HS_FILES)

fix-lint-folder:
	@test -n "$(FOLDER)" || (echo "Usage: make fix-lint-folder FOLDER=packages/canopy-core/src" && exit 1)
	@hlint --refactor --refactor-options="--inplace" $(FOLDER)
	@ormolu -i $(shell find $(FOLDER) -name '*.hs')
```

### Step 5: Add a smoke test

Add a `check-makefile` target that verifies the directories exist:

```makefile
check-makefile:
	@for dir in $(SRC_DIRS); do \
		test -d "$$dir" || (echo "ERROR: Directory $$dir not found" && exit 1); \
	done
	@echo "All source directories verified."
```

## Validation

```bash
make check-makefile  # Verify directories exist
make lint            # Should now actually find and check files
make format          # Should now actually format files
make build && make test
```

## Acceptance Criteria

- `make lint` processes all 276+ source files (reports count or errors)
- `make format` processes all source files
- `make check-makefile` passes
- `make build && make test` passes
- No references to `compiler/`, `builder/`, `terminal/` as source directories remain in Makefile
