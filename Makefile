# Plated — the phone does not follow main, so putting a build on it is a
# deliberate step. This is that step.

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

## Run the unit tests on a booted simulator (the news digest, deep links).
test:
	@xcodebuild -project Plated.xcodeproj -scheme Plated -configuration Debug \
		-destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
		-derivedDataPath build/DerivedData-sim test -only-testing:PlatedTests 2>&1 \
		| grep -E "error:|Test Case .* failed|Executed|TEST (SUCCEEDED|FAILED)"
