ROOT = $(dir $(realpath $(firstword $(MAKEFILE_LIST))))
SHELL := /bin/bash

export PATH := node_modules/.bin:$(PATH)

.PHONY: $(MAKECMDGOALS)

default: help

help:
	@echo "build: Build this project"
	@echo "test: Run all tests"
	@echo "test-unit: Run unit tests only"
	@echo "test-property: Run property tests only"
	@echo "test-integration: Run integration tests only"
	@echo "test-watch: Run tests in watch mode"
	@echo "test-coverage: Run tests with coverage report"
	@echo "test-coverage-check: Run tests with coverage and enforce 80% threshold"
	@echo "test-coverage-report: Show per-module coverage breakdown"
	@echo "test-coverage-badge: Generate coverage badge for documentation"
	@echo "test-build: Build tests without running them"
	@echo "test-deps: Install test dependencies"
	@echo "bench: Run compilation benchmarks (HTML report)"
	@echo "bench-quick: Run quick benchmarks (1s time limit)"
	@echo "bench-csv: Run benchmarks with CSV output"
	@echo "build-webidl: Build the canopy-webidl package"
	@echo "test-webidl: Run canopy-webidl tests"
	@echo "profile-build: Build with profiling enabled"
	@echo "profile-run: Run with time/allocation profiling"
	@echo "profile-heap: Run with heap profiling"
	@echo "release-binary: Build optimized, stripped binary for current platform"
	@echo "release-archive: Package binary into tar.gz/zip archive"
	@echo "format-check: Check formatting without modifying files (for CI)"
	@echo "release-checksum: Generate SHA256 checksum for release archive"

build:
	@stack install --fast --pedantic --ghc-options "-j +RTS -A128m -n2m -RTS"

clean:
	@stack clean

PACKAGE_DIRS = packages/canopy-core/src packages/canopy-builder/src packages/canopy-driver/src packages/canopy-query/src packages/canopy-terminal/src packages/canopy-terminal/impl packages/canopy-webidl/src test bench

lint:
	hlint -h .hlint.yaml --no-summary $(PACKAGE_DIRS) -j && \
	find $(PACKAGE_DIRS) -name "*.hs" -print0 | \
		xargs -P 8 -0 -I _ ormolu --ghc-opt=-XTypeApplications --mode=check _

fix-lint:
	@for dir in $(PACKAGE_DIRS); do \
		hlint -h .hlint.yaml --no-summary $$dir -j | \
		grep -oP "(?<=$$dir/).*?(?=:)" | xargs -I _ \
		hlint $$dir/_ -h .hlint.yaml --refactor --refactor-options="--inplace" -j &>/dev/null || true; \
	done
	@$(MAKE) format

fix-lint-folder:
	@if [ -z "$(FOLDER)" ]; then \
		echo "Usage: make fix-lint-folder FOLDER=<folder>"; \
		echo "Available folders: packages/canopy-core/src, packages/canopy-builder/src, etc."; \
		exit 1; \
	fi
	@hlint -h .hlint.yaml --no-summary $(FOLDER) -j | \
	grep -oP "(?<=$(FOLDER)/).*?(?=:)" | xargs -I _ \
	hlint $(FOLDER)/_ -h .hlint.yaml --refactor --refactor-options="--inplace" -j &>/dev/null || true
	@find $(FOLDER) -name '*.hs' -exec ormolu --ghc-opt=-XTypeApplications --mode=inplace {} \;

format:
	@find $(PACKAGE_DIRS) -name '*.hs' -exec ormolu --ghc-opt=-XTypeApplications --mode=inplace {} \;

format-check:
	@find $(PACKAGE_DIRS) -name "*.hs" -print0 | \
		xargs -P 8 -0 -I _ ormolu --ghc-opt=-XTypeApplications --mode=check _

test:
	@echo "Running all tests..."
	@stack test --fast canopy:canopy-test

test-match:
	@echo "Running specific tests..."
	@stack test --fast canopy:canopy-test --test-arguments "--pattern \"${PATTERN}\""

test-unit:
	@echo "Running unit tests..."
	@stack test --fast canopy:canopy-test --test-arguments "--pattern=Unit"

test-property:
	@echo "Running property tests..."
	@stack test --fast canopy:canopy-test --test-arguments "--pattern=Property"

test-integration:
	@echo "Running integration tests..."
	@stack test --fast canopy:canopy-test --test-arguments "--pattern=Integration"

test-watch:
	@echo "Running tests in watch mode..."
	@stack test --fast canopy:canopy-test --file-watch

test-coverage:
	@echo "Running tests with coverage..."
	@stack test --coverage --fast canopy:canopy-test
	@stack hpc report canopy:canopy-test --destdir=coverage-report 2>/dev/null || true
	@echo "Coverage report: coverage-report/hpc_index.html"

test-coverage-check: test-coverage
	@./scripts/check-coverage.sh 80

test-coverage-report:
	@./scripts/coverage-by-module.sh

test-coverage-badge:
	@./scripts/coverage-badge.sh

test-build:
	@echo "Building tests without running..."
	@stack build --test --no-run-tests --fast canopy:canopy-test

test-deps:
	@echo "Installing test dependencies..."
	@stack build --test --only-dependencies

bench:
	@echo "Running benchmarks..."
	@stack bench canopy:canopy-bench --benchmark-arguments '--output bench/report.html'

bench-quick:
	@echo "Running quick benchmarks..."
	@stack bench canopy:canopy-bench --benchmark-arguments '--time-limit 1'

bench-csv:
	@echo "Running benchmarks with CSV output..."
	@stack bench canopy:canopy-bench --benchmark-arguments '--csv bench/results.csv'

build-webidl:
	@stack build canopy-webidl

test-webidl:
	@stack test canopy-webidl

example:
	@make build
	@cd example && canopy make src/Main.can --output=canopy.js --verbose
	@cd ..

# -- Profiling targets -------------------------------------------------------

profile-build:
	@echo "Building with profiling enabled..."
	@stack build --profile --ghc-options="-fprof-auto -rtsopts"

profile-run:
	@echo "Running with time and allocation profiling..."
	@stack exec --profile -- canopy make src/Main.can +RTS -p -hT -l -RTS
	@echo "See canopy.prof for time/allocation breakdown"

profile-heap:
	@echo "Running with heap profiling..."
	@stack exec --profile -- canopy make src/Main.can +RTS -hc -p -RTS
	@hp2ps -c canopy.hp 2>/dev/null || echo "Run hp2ps manually: hp2ps -c canopy.hp"
	@echo "See canopy.ps for heap profile"

# -- Release targets ----------------------------------------------------------

DIST_DIR = dist
VERSION = $(shell grep '^version:' canopy.cabal | head -1 | awk '{print $$2}')
UNAME_S = $(shell uname -s)
UNAME_M = $(shell uname -m)

ifeq ($(UNAME_S),Linux)
  RELEASE_OS = linux
endif
ifeq ($(UNAME_S),Darwin)
  RELEASE_OS = darwin
endif

ifeq ($(UNAME_M),x86_64)
  RELEASE_ARCH = x86_64
endif
ifeq ($(UNAME_M),arm64)
  RELEASE_ARCH = aarch64
endif
ifeq ($(UNAME_M),aarch64)
  RELEASE_ARCH = aarch64
endif

RELEASE_PLATFORM = $(RELEASE_OS)-$(RELEASE_ARCH)
RELEASE_ARCHIVE = canopy-$(VERSION)-$(RELEASE_PLATFORM).tar.gz

release-binary:
	@echo "Building optimized binary..."
	@stack build --ghc-options="-O2" --copy-bins --local-bin-path=$(DIST_DIR)
	@strip $(DIST_DIR)/canopy 2>/dev/null || true
	@echo "Binary: $(DIST_DIR)/canopy"
	@ls -lh $(DIST_DIR)/canopy

release-archive: release-binary
	@echo "Packaging $(RELEASE_ARCHIVE)..."
	@tar -czf $(RELEASE_ARCHIVE) -C $(DIST_DIR) canopy
	@echo "Archive: $(RELEASE_ARCHIVE)"
	@ls -lh $(RELEASE_ARCHIVE)

release-checksum: release-archive
	@echo "Generating checksum..."
	@sha256sum $(RELEASE_ARCHIVE) > SHA256SUMS.txt
	@cat SHA256SUMS.txt