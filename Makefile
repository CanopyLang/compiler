ROOT = $(dir $(realpath $(firstword $(MAKEFILE_LIST))))
SHELL := /bin/bash

export PATH := node_modules/.bin:$(PATH)

.PHONY: $(MAKECMDGOALS)

default: help

help:
	@echo "build: Build this project"

build:
	@stack install --fast --pedantic --ghc-options "-j +RTS -A128m -n2m -RTS"

clean:
	@stack clean

fix-lint:
	@hlint -h .hlint.yaml --no-summary src -j | \
	grep -oP '(?<=src/).*?(?=:)' | xargs -I _ \
	hlint src/_ -h .hlint.yaml --refactor --refactor-options="--inplace" -j &>/dev/null
	@$(MAKE) format

format:
	@find src test -name '*.hs' -exec ormolu --ghc-opt=-XTypeApplications --mode=inplace {} \;
