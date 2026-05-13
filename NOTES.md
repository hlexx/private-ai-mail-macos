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

## Manual smoke test: end-to-end Gmail account flow

1. Delete the sandbox container to start fresh:
   ```bash
   rm -rf ~/Library/Containers/com.hlexx.privateaimail/
   ```
2. Build and run `MacApp` via Xcode (Cmd+R) or:
   ```bash
   tuist generate --no-open
   xcodebuild build -workspace PrivateAIMail.xcworkspace -scheme MacApp -configuration Debug -destination 'platform=macOS'
   open DerivedData/PrivateAIMail/Build/Products/Debug/PrivateAIMail.app
   ```
3. Open Settings (Cmd+,) → Accounts tab.
4. Click "Add Gmail account". The system browser opens the Google OAuth
   consent screen.
5. Sign in with a Gmail account and grant the requested scopes
   (`gmail.readonly`, `gmail.metadata`, `userinfo.email`).
6. The Settings tab shows a progress bar while bootstrap sync runs.
7. Within ~60 seconds the sidebar in the main window shows the new
   account, and the thread list populates with the last 30 days of
   Gmail threads sorted by most recent.
8. Select a thread to see its messages in the right pane.
9. Press Cmd+R to trigger incremental sync — new messages should
   appear without restarting the app.
