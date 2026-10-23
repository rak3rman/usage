SHELL := /bin/bash

.PHONY: test project build run

test:
	cd Packages/UsageKit && swift test

project:
	xcodegen generate

build: project
	@set -o pipefail; xcodebuild -project Usage.xcodeproj -scheme Usage -configuration Debug \
		-derivedDataPath build build | grep -E "error:|warning:|BUILD"

run: build
	open build/Build/Products/Debug/Usage.app
