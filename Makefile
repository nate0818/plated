# Plated — the phone does not follow main, so putting a build on it is a
# deliberate step. This is that step.

# pipefail below is a bash option; /bin/sh on macOS is bash in POSIX mode
# and honours it, but say so rather than rely on it.
SHELL := /bin/bash

.PHONY: phone phone-install phone-purge tokens design test

## Build the working tree, install it on the iPhone, and launch it.
phone:
	@scripts/phone

## Install without launching.
phone-install:
	@scripts/phone --no-launch

## Install and launch with the CloudKit + local store wiped (Debug only).
phone-purge:
	@scripts/phone -- -plated-purge-cloud

## Check the widget's copied design tokens against Theme.swift.
tokens:
	@scripts/check-tokens

## Check the codebase against the DESIGN.md rules a machine can check.
design:
	@scripts/check-design

## Run the unit tests on a simulator (the news digest, deep links, the
## household merge). Pinned by id rather than name: three simulators are
## called "iPhone 17 Pro" and xcodebuild silently picked the iOS 27 one,
## not the booted one. Override with PLATED_SIM=<udid>. The tests run
## inside the app host and rewrite that simulator's app-group ledgers, so
## point this at a simulator no other session is driving. Two sessions on
## one simulator do not fail a test: the second run is killed while it is
## still bootstrapping, so it reports zero tests executed and exit 65,
## which reads as a broken build rather than a collision. A green run whose
## count came back low was probably interleaved with somebody else's.
PLATED_SIM ?= FDC94B74-3C20-49A0-8174-6188E4BF45B1
test:
	@set -o pipefail; xcodebuild -project Plated.xcodeproj -scheme Plated -configuration Debug \
		-destination 'platform=iOS Simulator,id=$(PLATED_SIM)' \
		-derivedDataPath build/DerivedData-sim test -only-testing:PlatedTests 2>&1 \
		| grep -E "error:|Test Case .* failed|Executed|TEST (SUCCEEDED|FAILED)"
