#!/usr/bin/env bash
# Runs the Trust MVP regression release gate.
#
# Default mode is intended for the local release loop:
#   ./scripts/verify-trust-mvp.sh
#
# Full release gate, including generated workspace and macOS app build:
#   FULL_TRUST_MVP_GATE=1 ./scripts/verify-trust-mvp.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DRY_RUN="${VERIFY_TRUST_MVP_DRY_RUN:-0}"
FULL_GATE="${FULL_TRUST_MVP_GATE:-0}"

section() {
    printf '\n== %s ==\n' "$1"
}

print_command() {
    printf '+'
    for arg in "$@"; do
        printf ' %q' "$arg"
    done
    printf '\n'
}

run() {
    print_command "$@"
    if [[ "$DRY_RUN" == "1" ]]; then
        return 0
    fi
    "$@"
}

run_in() {
    local dir="$1"
    shift
    printf '+ cd %q\n' "$dir"
    if [[ "$DRY_RUN" == "1" ]]; then
        print_command "$@"
        return 0
    fi
    (
        cd "$dir"
        print_command "$@"
        "$@"
    )
}

require_command() {
    local name="$1"
    if [[ "$DRY_RUN" == "1" ]]; then
        printf 'dry-run: would require %s\n' "$name"
        return 0
    fi
    if ! command -v "$name" >/dev/null 2>&1; then
        printf 'ERROR: required command not found: %s\n' "$name" >&2
        return 1
    fi
}

run_forbidden_grep() {
    local label="$1"
    local pattern="$2"
    shift 2

    printf 'checking: %s\n' "$label"
    if [[ "$DRY_RUN" == "1" ]]; then
        printf 'dry-run: rg -n -e %q ...\n' "$pattern"
        return 0
    fi

    local output
    local status
    set +e
    output="$(rg -n -e "$pattern" "$@" 2>&1)"
    status=$?
    set -e

    if [[ $status -eq 0 ]]; then
        printf 'ERROR: privacy grep failed: %s\n' "$label" >&2
        printf '%s\n' "$output" >&2
        return 1
    fi
    if [[ $status -ne 1 ]]; then
        printf 'ERROR: privacy grep command failed for %s\n' "$label" >&2
        printf '%s\n' "$output" >&2
        return "$status"
    fi
}

check_privacy_logger_boundary() {
    local allowed='Packages/Core/AppFoundation/Sources/AppFoundation/PrivacyObservability.swift'
    local pattern='(^|[^A-Za-z0-9_])(Logger\(|os_log\(|logger\.)'

    printf 'checking: direct Logger/os_log use stays behind PrivacyObservability\n'
    if [[ "$DRY_RUN" == "1" ]]; then
        printf 'dry-run: rg -n -e %q ... | grep -v %q\n' "$pattern" "$allowed"
        return 0
    fi

    local output
    local status
    set +e
    output="$(rg -n -e "$pattern" Apps Packages \
        --glob '*.swift' \
        --glob '!**/.build/**' \
        --glob '!**/Tests/**' \
        --glob '!**/*Tests.swift' \
        | grep -v "$allowed")"
    status=$?
    set -e

    if [[ $status -eq 0 ]]; then
        printf 'ERROR: direct Logger/os_log use must go through PrivacyObservability\n' >&2
        printf '%s\n' "$output" >&2
        return 1
    fi
    if [[ $status -ne 1 ]]; then
        printf 'ERROR: Logger/os_log privacy boundary check failed\n' >&2
        printf '%s\n' "$output" >&2
        return "$status"
    fi
}

swift_package_test_if_present() {
    local package_name="$1"
    local package_dir="$2"
    local absolute_package_dir="$PROJECT_ROOT/$package_dir"

    if [[ -f "$absolute_package_dir/Package.swift" ]]; then
        local swift_test_args=()
        if [[ -d "$absolute_package_dir/Tests" ]] \
            && ! rg -q -e '(^import XCTest|XCTestCase)' "$absolute_package_dir/Tests" --glob '*.swift'; then
            swift_test_args+=(--disable-xctest)
        fi
        run_in "$absolute_package_dir" swift test "${swift_test_args[@]}"
    else
        printf 'skip: %s package not present at %s\n' "$package_name" "$package_dir"
    fi
}

cd "$PROJECT_ROOT"

section "Tooling"
require_command git
require_command rg
require_command swift
require_command swiftlint
if [[ "$FULL_GATE" == "1" ]]; then
    require_command tuist
    require_command xcodebuild
fi

section "Repository hygiene"
run git diff --check

section "SwiftLint"
run swiftlint --strict --reporter xcode

section "Swift package tests"
swift_package_test_if_present "MailDomain" "Packages/Mail/MailDomain"
swift_package_test_if_present "MailProviders" "Packages/Mail/MailProviders"
swift_package_test_if_present "MailSync" "Packages/Mail/MailSync"
swift_package_test_if_present "MailIndex" "Packages/Mail/MailIndex"
swift_package_test_if_present "Persistence" "Packages/Core/Persistence"
swift_package_test_if_present "AuthKit" "Packages/Auth/AuthKit"
swift_package_test_if_present "ComposeFeature" "Packages/Features/ComposeFeature"
swift_package_test_if_present "InboxFeature" "Packages/Features/InboxFeature"
swift_package_test_if_present "ThreadFeature" "Packages/Features/ThreadFeature"
swift_package_test_if_present "SettingsFeature" "Packages/Features/SettingsFeature"
swift_package_test_if_present "AttachmentKit" "Packages/Attachments/AttachmentKit"
swift_package_test_if_present "AttachmentRAG" "Packages/Attachments/AttachmentRAG"

section "Privacy grep"
run_forbidden_grep \
    "hard-coded bearer token literals" \
    'Bearer[[:space:]]+[A-Za-z0-9._~+/=-]{16,}' \
    Apps Packages docs \
    --glob '*.swift' \
    --glob '*.md' \
    --glob '!**/.build/**' \
    --glob '!**/Tests/**' \
    --glob '!**/*Tests.swift'

run_forbidden_grep \
    "hard-coded refresh token or client secret values" \
    '(refresh_token|client_secret|clientSecret)[[:space:]]*[:=][[:space:]]*["'\''][A-Za-z0-9._~+/=-]{8,}' \
    Apps Packages docs \
    --glob '*.swift' \
    --glob '*.md' \
    --glob '!**/.build/**' \
    --glob '!**/Tests/**' \
    --glob '!**/*Tests.swift'

run_forbidden_grep \
    "unsafe print statements in non-test Swift" \
    '(^|[^A-Za-z0-9_])print\(' \
    Apps Packages \
    --glob '*.swift' \
    --glob '!**/.build/**' \
    --glob '!**/Tests/**' \
    --glob '!**/*Tests.swift'

run_forbidden_grep \
    "tokens, secrets, or credentials in logs" \
    '(Logger|logger\.|os_log|print\().*(token|secret|authorization|bearer|credential|refresh)' \
    Apps Packages \
    --glob '*.swift' \
    --glob '!**/.build/**' \
    --glob '!**/Tests/**' \
    --glob '!**/*Tests.swift'

run_forbidden_grep \
    "raw body, prompt, payload, or attachment bytes in logs" \
    '(Logger|logger\.|os_log|print\().*(body|html|mime|payload|prompt|modelOutput|model output|attachmentBytes|rawAttachment|attachment bytes|bytes|deltaLink|history)' \
    Apps Packages \
    --glob '*.swift' \
    --glob '!**/.build/**' \
    --glob '!**/Tests/**' \
    --glob '!**/*Tests.swift'

check_privacy_logger_boundary

section "Full app build"
if [[ "$FULL_GATE" == "1" ]]; then
    run tuist generate --no-open
    run xcodebuild build \
        -workspace PrivateAIMail.xcworkspace \
        -scheme MacApp \
        -configuration Debug \
        -destination 'platform=macOS' \
        CODE_SIGNING_ALLOWED=NO
else
    printf 'Skipping Tuist generation and xcodebuild in default mode.\n'
    printf 'Run the full release command when cutting a release:\n'
    printf '  FULL_TRUST_MVP_GATE=1 ./scripts/verify-trust-mvp.sh\n'
fi

section "Trust MVP gate complete"
