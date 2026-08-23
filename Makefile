# Plated — the phone does not follow main, so putting a build on it is a
# deliberate step. This is that step.

.PHONY: phone phone-install phone-purge

## Build the working tree, install it on the iPhone, and launch it.
phone:
	@scripts/phone

## Install without launching.
phone-install:
	@scripts/phone --no-launch

## Install and launch with the CloudKit + local store wiped (Debug only).
phone-purge:
	@scripts/phone -- -plated-purge-cloud
