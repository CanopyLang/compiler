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
	@echo "test-build: Build tests without running them"
	@echo "test-deps: Install test dependencies"
	@echo "bench: Run compilation benchmarks (HTML report)"
	@echo "bench-quick: Run quick benchmarks (1s time limit)"
	@echo "bench-csv: Run benchmarks with CSV output"

build:
	@stack install --fast --pedantic --ghc-options "-j +RTS -A128m -n2m -RTS"

clean:
	@stack clean

PACKAGE_DIRS = packages/canopy-core/src packages/canopy-builder/src packages/canopy-driver/src packages/canopy-query/src packages/canopy-terminal/src packages/canopy-terminal/impl test

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
	@echo "Coverage report generated in .stack-work/install/*/doc/"

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

example:
	@make build
	@cd example && canopy make src/Main.can --output=canopy.js --verbose
	@cd ..