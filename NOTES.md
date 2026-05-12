# Skeleton notes

## Why MLX is not yet linked

`Packages/AI/AIRuntime/Package.swift` and `Packages/AI/AIEmbeddings/Package.swift`
intentionally do **not** declare a dependency on
[`ml-explore/mlx-swift`](https://github.com/ml-explore/mlx-swift) in this
skeleton iteration.

Reasons:
1. MLX ships Metal shader source that requires the Xcode 26 **Metal Toolchain**
   component (download via `xcodebuild -downloadComponent MetalToolchain`).
   We don't want CI runners or contributors to pay that cost until we actually
   call MLX.
2. The skeleton's job is to validate the dependency graph and app shell, not
   to compile ML kernels.

When we start the **AI runtime iteration** (step 6 of the §15 roadmap), we
will:
- Add `.package(url: "https://github.com/ml-explore/mlx-swift.git", from: "0.20.0")`
  back to the two packages.
- Document the Metal Toolchain install step in the README.
- Update CI to download the Metal Toolchain.

The design decision (MLX primary + llama.cpp escape hatch) is unchanged.
See [§14 of the macOS design doc](../EMAIL_ALF/14_macos_app_design.md#142-чего-не-делаем-сейчас-чтобы-не-тащить-лишнее), decision 3.

## Tuist file layout

`Tuist/Config.swift` works but generates a deprecation warning. Migrate to
`Tuist.swift` at repo root in a follow-up cleanup.

## What "build green" means in this skeleton

- `tuist generate` succeeds.
- `xcodebuild build -workspace PrivateAIMail.xcworkspace -scheme MacApp` succeeds.
- Each `Packages/*/*/` has a green `swift test` running one placeholder test.

There is **no functional behavior** yet — opening `MacApp` shows a 3-pane
`NavigationSplitView` with `ContentUnavailableView` placeholders in two of
the three columns and a static "No accounts connected" list in the sidebar.
