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

build:
	@stack install --fast --pedantic --ghc-options "-j +RTS -A128m -n2m -RTS"

clean:
	@stack clean

fix-lint:
	@for dir in compiler builder terminal test; do \
		hlint -h .hlint.yaml --no-summary $$dir -j | \
		grep -oP "(?<=$$dir/).*?(?=:)" | xargs -I _ \
		hlint $$dir/_ -h .hlint.yaml --refactor --refactor-options="--inplace" -j &>/dev/null || true; \
	done
	@$(MAKE) format

fix-lint-folder:
	@if [ -z "$(FOLDER)" ]; then \
		echo "Usage: make fix-lint-folder FOLDER=<folder>"; \
		echo "Available folders: compiler, builder, terminal, test"; \
		exit 1; \
	fi
	@hlint -h .hlint.yaml --no-summary $(FOLDER) -j | \
	grep -oP "(?<=$(FOLDER)/).*?(?=:)" | xargs -I _ \
	hlint $(FOLDER)/_ -h .hlint.yaml --refactor --refactor-options="--inplace" -j &>/dev/null || true
	@find $(FOLDER) -name '*.hs' -exec ormolu --ghc-opt=-XTypeApplications --mode=inplace {} \;

format:
	@find builder compiler terminal test -name '*.hs' -exec ormolu --ghc-opt=-XTypeApplications --mode=inplace {} \;

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

example:
	@make build
	@cd example && canopy make src/Main.can --output=canopy.js --verbose
	@cd ..