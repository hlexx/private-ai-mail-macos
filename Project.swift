import ProjectDescription

// MARK: - Local packages

private let localPackages: [Package] = [
    // Core
    .local(path: "Packages/Core/AppFoundation"),
    .local(path: "Packages/Core/DesignSystem"),
    .local(path: "Packages/Core/Persistence"),
    // Mail
    .local(path: "Packages/Mail/MailDomain"),
    .local(path: "Packages/Mail/MailProviders"),
    .local(path: "Packages/Mail/MailIndex"),
    .local(path: "Packages/Mail/MailSync"),
    // AI
    .local(path: "Packages/AI/AIPrompts"),
    .local(path: "Packages/AI/AIEmbeddings"),
    .local(path: "Packages/AI/AIRuntime"),
    .local(path: "Packages/AI/AIKit"),
    .local(path: "Packages/AI/AIEvals"),
    // Attachments
    .local(path: "Packages/Attachments/AttachmentKit"),
    .local(path: "Packages/Attachments/AttachmentRAG"),
    // Auth
    .local(path: "Packages/Auth/AuthKit"),
    // Integrations
    .local(path: "Packages/Integrations/IntegrationDomain"),
    .local(path: "Packages/Integrations/IntegrationBroker"),
    .local(path: "Packages/Integrations/IntegrationConnectors"),
    // Features
    .local(path: "Packages/Features/InboxFeature"),
    .local(path: "Packages/Features/ThreadFeature"),
    .local(path: "Packages/Features/ComposeFeature"),
    .local(path: "Packages/Features/BriefFeature"),
    .local(path: "Packages/Features/ActionsFeature"),
    .local(path: "Packages/Features/SettingsFeature"),
    .local(path: "Packages/Features/TranslationFeature"),
]

// Features linked into the MacApp target. Core/Mail/AI/etc are pulled in transitively.
private let appFeatureDeps: [TargetDependency] = [
    .package(product: "AppFoundation"),
    .package(product: "InboxFeature"),
    .package(product: "ThreadFeature"),
    .package(product: "ComposeFeature"),
    .package(product: "BriefFeature"),
    .package(product: "ActionsFeature"),
    .package(product: "SettingsFeature"),
    .package(product: "DesignSystem"),
    .package(product: "AIRuntime"),
    .package(product: "AttachmentRAG"),
    .package(product: "TranslationFeature"),
]

// MARK: - Project

let project = Project(
    name: "PrivateAIMail",
    organizationName: "hlexx",
    packages: localPackages,
    settings: .settings(
        base: [
            "SWIFT_VERSION": "6.0",
            "SWIFT_STRICT_CONCURRENCY": "complete",
            "ENABLE_HARDENED_RUNTIME": "YES",
            "DEAD_CODE_STRIPPING": "YES",
        ],
        configurations: [
            .debug(name: "Debug"),
            .release(name: "Release"),
        ]
    ),
    targets: [
        .target(
            name: "MacApp",
            destinations: .macOS,
            product: .app,
            productName: "PrivateAIMail",
            bundleId: "com.hlexx.privateaimail",
            deploymentTargets: .macOS("15.0"),
            infoPlist: .file(path: "Apps/MacApp/Info.plist"),
            sources: ["Apps/MacApp/Sources/**"],
            resources: [
                // App icon ships as a pre-compiled `.icns` (via `iconutil`)
                // because Tuist 4.193 does not invoke `actool` on the
                // asset catalog for this target setup. Source PNGs live
                // in Resources/Assets.xcassets/AppIcon.appiconset/ and are
                // regenerated from `tools/make-icon.swift` (see NOTES.md).
                "Apps/MacApp/Resources/AppIcon.icns",
                "Apps/MacApp/Resources/Localizable.xcstrings",
                "Apps/MacApp/Resources/Fonts/**",
            ],
            entitlements: .file(path: "Apps/MacApp/PrivateAIMail.entitlements"),
            dependencies: appFeatureDeps + [
                .xcframework(path: "Frameworks/Sparkle.xcframework"),
            ],
            settings: .settings(
                base: [
                    "CODE_SIGN_STYLE": "Automatic",
                    "DEVELOPMENT_TEAM": "",
                    "MARKETING_VERSION": "0.1.32-alpha",
                    "CURRENT_PROJECT_VERSION": "132",
                ]
            )
        ),
        .target(
            name: "MacAppTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.hlexx.privateaimail.tests",
            deploymentTargets: .macOS("15.0"),
            infoPlist: .default,
            sources: ["Apps/MacApp/Tests/**"],
            dependencies: [.target(name: "MacApp")]
        ),
    ],
    schemes: [
        .scheme(
            name: "MacApp",
            shared: true,
            buildAction: .buildAction(targets: ["MacApp"]),
            testAction: .targets(["MacAppTests"]),
            runAction: .runAction(executable: "MacApp")
        ),
    ]
)
