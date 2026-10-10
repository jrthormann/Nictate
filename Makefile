# Nictate: a macOS menu bar app that copies text from anywhere on your screen.
# Copyright (c) 2026 jrthormann. MIT License, see LICENSE.

.PHONY: setup build test-app test ui-test strings sources check coverage run install dmg

build:      ## Build build/Nictate.app
	./scripts/build-app.sh

test-app:   ## Build build/NictateTest.app, the isolated QA app with its own Keychain item and history (see scripts/variants)
	NICTATE_VARIANT=test ./scripts/build-app.sh

setup:      ## Create the local signing identity once, in its own keychain (asks for a new password)
	scripts/create_signing_cert.sh

test:       ## Run unit and OCR tests
	Tests/run_tests.sh

ui-test:    ## Run the UI smoke tests (needs a window server)
	Tests/run_ui_tests.sh

strings:    ## Verify es/en localization is complete
	scripts/check_strings.py

sources:    ## Forbid NSLog/print in Sources and files over 400 lines
	scripts/check_sources.sh

check: test ui-test strings sources   ## Everything CI runs, minus the build

coverage:   ## Print line coverage of the unit tests per source file (informational, never fails)
	-rm -rf build/coverage && mkdir -p build/coverage
	-OPT="-profile-generate -profile-coverage-mapping" LLVM_PROFILE_FILE="$(CURDIR)/build/coverage/run-%p.profraw" Tests/run_tests.sh
	-xcrun llvm-profdata merge -sparse build/coverage/*.profraw -o build/coverage/run.profdata
	-xcrun llvm-cov report build/run_tests -instr-profile=build/coverage/run.profdata Sources/Nictate/*.swift

run: build  ## Build, quit any running copy, and launch the new one
	-@pkill -x Nictate && sleep 1
	open build/Nictate.app

install: build  ## Build, quit Nictate, put the new copy in /Applications and launch it
	-@pkill -x Nictate && sleep 1
	rm -rf /Applications/Nictate.app.new
	ditto build/Nictate.app /Applications/Nictate.app.new
	rm -rf /Applications/Nictate.app && mv /Applications/Nictate.app.new /Applications/Nictate.app
	open /Applications/Nictate.app

dmg:        ## Build build/release/<version>/Nictate-<version>.dmg from a commit; BUILD_NUMBER required (docs/RELEASING.md)
	./scripts/build-dmg.sh

