SHELL := /bin/zsh

APP_NAME := OneTwenty
BUILD_CONFIG := release
BUILD_DIR := .build/$(BUILD_CONFIG)
BINARY := $(BUILD_DIR)/$(APP_NAME)
APP_BUNDLE := dist/OneTwenty.app

.PHONY: build run clean app bundle zip open-app release-check test notarize

build:
	swift build -c $(BUILD_CONFIG)

test:
	swift test

run: build
	@pkill -x $(APP_NAME) || true
	@echo "Launching $(APP_NAME) from $(BINARY) ..."
	@$(BINARY) &
	@echo "(Launched in background)"

clean:
	rm -rf .build dist

app bundle:
	@./scripts/build_app.sh

zip: app
	@./scripts/package_zip.sh

open-app: app
	open "$(APP_BUNDLE)"

notarize:
	@./scripts/notarize.sh

release-check: build test zip
	@echo "Release checks complete."
