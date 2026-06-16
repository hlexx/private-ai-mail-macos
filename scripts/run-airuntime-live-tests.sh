#!/usr/bin/env bash
# Runs AIRuntime live MLX tests from SwiftPM.
#
# SwiftPM test bundles do not always expose mlx-swift's default.metallib
# resource the same way the Xcode-built app bundle does. This runner creates a
# temporary symlink for the test process and removes it on exit.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PACKAGE_DIR="$PROJECT_ROOT/Packages/AI/AIRuntime"
SHIM_PATH="$PACKAGE_DIR/default.metallib"
MODEL_DIR="$HOME/Library/Application Support/PrivateAIMail/models/gemma-4-e2b-it-4bit"
TEST_FILTER="${RB_LIVE_TEST_FILTER:-MLXLLMRunnerLiveTests}"

cleanup() {
    if [[ -L "$SHIM_PATH" && "${CREATED_SHIM:-0}" == "1" ]]; then
        rm "$SHIM_PATH"
    fi
}
trap cleanup EXIT

fail() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

find_metallib() {
    if [[ -n "${RB_MLX_METALLIB_PATH:-}" ]]; then
        [[ -f "$RB_MLX_METALLIB_PATH" ]] || fail "RB_MLX_METALLIB_PATH does not point to a file"
        printf '%s\n' "$RB_MLX_METALLIB_PATH"
        return 0
    fi

    local derived_data="$HOME/Library/Developer/Xcode/DerivedData"
    [[ -d "$derived_data" ]] || fail "Xcode DerivedData not found at $derived_data"

    local found
    found="$(
        find "$derived_data" \
            -path '*/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib' \
            -print0 2>/dev/null \
            | xargs -0 ls -t 2>/dev/null \
            | head -n 1
    )"

    [[ -n "$found" ]] || fail "default.metallib not found. Build MacApp once, then rerun this script."
    printf '%s\n' "$found"
}

[[ -d "$PACKAGE_DIR" ]] || fail "AIRuntime package not found at $PACKAGE_DIR"
[[ -d "$MODEL_DIR" ]] || fail "local model not found at $MODEL_DIR"

METALLIB_PATH="$(find_metallib)"

if [[ -e "$SHIM_PATH" || -L "$SHIM_PATH" ]]; then
    if [[ -L "$SHIM_PATH" && "$(readlink "$SHIM_PATH")" == "$METALLIB_PATH" ]]; then
        CREATED_SHIM=0
    else
        fail "refusing to overwrite existing $SHIM_PATH"
    fi
else
    ln -s "$METALLIB_PATH" "$SHIM_PATH"
    CREATED_SHIM=1
fi

printf 'Using metallib: %s\n' "$METALLIB_PATH"
printf 'Running AIRuntime live tests: %s\n' "$TEST_FILTER"

(
    cd "$PACKAGE_DIR"
    RB_RUN_REAL_MLX_TESTS=1 swift test --filter "$TEST_FILTER"
)
