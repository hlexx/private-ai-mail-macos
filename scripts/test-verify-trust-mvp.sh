#!/usr/bin/env bash
# Fast structural tests for scripts/verify-trust-mvp.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERIFY_SCRIPT="$PROJECT_ROOT/scripts/verify-trust-mvp.sh"

fail() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    if [[ "$haystack" != *"$needle"* ]]; then
        fail "expected output to contain: $needle"
    fi
}

bash -n "$VERIFY_SCRIPT"

default_output="$(cd "$PROJECT_ROOT" && VERIFY_TRUST_MVP_DRY_RUN=1 "$VERIFY_SCRIPT")"
assert_contains "$default_output" "git diff --check"
assert_contains "$default_output" "swiftlint --strict --reporter xcode"
assert_contains "$default_output" "swift test --disable-xctest"
assert_contains "$default_output" "Packages/Mail/MailDomain"
assert_contains "$default_output" "Packages/Mail/MailProviders"
assert_contains "$default_output" "Packages/Mail/MailSync"
assert_contains "$default_output" "Packages/Mail/MailIndex"
assert_contains "$default_output" "Packages/Core/Persistence"
assert_contains "$default_output" "Packages/Auth/AuthKit"
assert_contains "$default_output" "Packages/Features/ComposeFeature"
assert_contains "$default_output" "Packages/Features/InboxFeature"
assert_contains "$default_output" "Packages/Features/ThreadFeature"
assert_contains "$default_output" "Packages/Features/SettingsFeature"
assert_contains "$default_output" "Packages/Attachments/AttachmentKit"
assert_contains "$default_output" "Packages/Attachments/AttachmentRAG"
assert_contains "$default_output" "hard-coded bearer token literals"
assert_contains "$default_output" "unsafe print statements in non-test Swift"
assert_contains "$default_output" "raw body, prompt, payload, or attachment bytes in logs"
assert_contains "$default_output" "FULL_TRUST_MVP_GATE=1 ./scripts/verify-trust-mvp.sh"

full_output="$(cd "$PROJECT_ROOT" && VERIFY_TRUST_MVP_DRY_RUN=1 FULL_TRUST_MVP_GATE=1 "$VERIFY_SCRIPT")"
assert_contains "$full_output" "tuist generate --no-open"
assert_contains "$full_output" "xcodebuild build"
assert_contains "$full_output" "CODE_SIGNING_ALLOWED=NO"

printf 'verify-trust-mvp script tests passed\n'
