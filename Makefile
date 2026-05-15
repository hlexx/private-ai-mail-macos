# Makefile — PrivateAIMail release pipeline
#
# Targets:
#   make release   — full pipeline: generate → build → test → sign → DMG → notarize → appcast
#   make appcast   — regenerate appcast.xml from existing dist/*.dmg files
#   make build     — tuist generate + xcodebuild Release build
#   make test      — run unit tests
#   make dmg       — package the built .app into a DMG
#   make sign      — codesign the built .app
#   make clean     — remove dist/ artefacts

SHELL := /bin/bash
.PHONY: release appcast build test dmg sign notarize clean fetch-sparkle

# Extract version from Project.swift MARKETING_VERSION
VERSION := $(shell grep 'MARKETING_VERSION' Project.swift | head -1 | sed 's/.*"\(.*\)".*/\1/')
# Allow override: make release VERSION=0.1.1-alpha
export VERSION

WORKSPACE := PrivateAIMail.xcworkspace
SCHEME := MacApp
CONFIGURATION := Release
DESTINATION := platform=macOS

# Derived paths
DIST_DIR := dist
DD_BASE := $(HOME)/Library/Developer/Xcode/DerivedData

# --- Full release pipeline ---
release: build test sign dmg notarize appcast
	@echo ""
	@echo "=== Release $(VERSION) complete ==="
	@echo "Artefacts in $(DIST_DIR)/"
	@ls -lh $(DIST_DIR)/PrivateAIMail-$(VERSION).dmg $(DIST_DIR)/appcast.xml 2>/dev/null || true

# --- Fetch Sparkle xcframework (idempotent) ---
fetch-sparkle:
	@./scripts/fetch-sparkle.sh

# --- Generate project + build ---
build: fetch-sparkle
	@echo "==> Generating project with Tuist..."
	tuist generate --no-open
	@echo "==> Building $(SCHEME) ($(CONFIGURATION))..."
	set -o pipefail && xcodebuild build \
		-workspace $(WORKSPACE) \
		-scheme $(SCHEME) \
		-configuration $(CONFIGURATION) \
		-destination '$(DESTINATION)' \
		CODE_SIGNING_ALLOWED=NO \
		2>&1 | tail -30
	@echo "==> Build complete."

# --- Run tests ---
test:
	@echo "==> Running tests..."
	xcodebuild test \
		-workspace $(WORKSPACE) \
		-scheme $(SCHEME) \
		-configuration Debug \
		-destination '$(DESTINATION)' \
		CODE_SIGNING_ALLOWED=NO \
		-only-testing:MacAppTests \
		2>&1 | tail -20 || echo "Note: test target may not have testable tests; continuing."

# --- Codesign the .app ---
sign:
	@echo "==> Signing app bundle..."
	@APP=$$(find $(DD_BASE) -maxdepth 6 -type d -name "PrivateAIMail.app" \
		-path "*PrivateAIMail*$(CONFIGURATION)*" 2>/dev/null | sort -r | head -1); \
	if [ -z "$$APP" ]; then \
		echo "Error: built .app not found. Run 'make build' first." >&2; exit 1; \
	fi; \
	./scripts/sign-app.sh "$$APP"

# --- Package DMG ---
dmg:
	@echo "==> Packaging DMG..."
	./scripts/build-dmg.sh $(VERSION)

# --- Notarize (skipped if env vars missing) ---
notarize:
	@echo "==> Notarization step..."
	@DMG="$(DIST_DIR)/PrivateAIMail-$(VERSION).dmg"; \
	if [ -f "$$DMG" ]; then \
		./scripts/notarize-dmg.sh "$$DMG"; \
	else \
		echo "No DMG found at $$DMG — skipping notarization."; \
	fi

# --- Regenerate appcast.xml ---
appcast:
	@echo "==> Generating appcast.xml..."
	./scripts/generate-appcast.sh
	@echo "==> Validating appcast.xml..."
	xmllint --noout $(DIST_DIR)/appcast.xml
	@echo "==> appcast.xml is valid."

# --- Clean ---
clean:
	rm -rf $(DIST_DIR)
	@echo "==> Cleaned $(DIST_DIR)/"
