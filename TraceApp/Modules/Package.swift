// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "Modules",
  platforms: [
    .macOS(.v15),
  ],
  products: [
    .library(
      name: "SharedUI",
      targets: ["SharedUI"]
    ),
    .library(
      name: "AppKitExtensions",
      targets: ["AppKitExtensions"]
    ),
    .library(
      name: "DiffKit",
      targets: ["DiffKit"]
    ),
    .library(
      name: "ExtensionCore",
      targets: ["ExtensionCore"]
    ),
    .library(
      name: "FileDrop",
      targets: ["FileDrop"]
    ),
    .library(
      name: "FileVersion",
      targets: ["FileVersion"]
    ),
    .library(
      name: "FontPicker",
      targets: ["FontPicker"]
    ),
    .library(
      name: "Previewer",
      targets: ["Previewer"]
    ),
    .library(
      name: "SettingsUI",
      targets: ["SettingsUI"]
    ),
    .library(
      name: "Statistics",
      targets: ["Statistics"]
    ),
    .library(
      name: "TextBundle",
      targets: ["TextBundle"]
    ),
    .library(
      name: "TextCompletion",
      targets: ["TextCompletion"]
    ),
  ],
  dependencies: [
    .package(path: "../TraceCore"),
    .package(path: "../TraceKit"),
    .package(path: "../TraceTools"),
  ],
  targets: [
    .target(
      name: "SharedUI",
      dependencies: ["AppKitExtensions"],
      path: "Sources/SharedUI",
      swiftSettings: [
        .enableExperimentalFeature("StrictConcurrency")
      ],
      plugins: [
        .plugin(name: "SwiftLint", package: "TraceTools"),
      ]
    ),
    .target(
      name: "AppKitExtensions",
      path: "Sources/AppKitExtensions",
      swiftSettings: [
        .enableExperimentalFeature("StrictConcurrency")
      ],
      plugins: [
        .plugin(name: "SwiftLint", package: "TraceTools"),
      ]
    ),
    .target(
      name: "DiffKit",
      path: "Sources/DiffKit",
      resources: [
        .process("Resources"),
      ],
      swiftSettings: [
        .enableExperimentalFeature("StrictConcurrency")
      ],
      plugins: [
        .plugin(name: "SwiftLint", package: "TraceTools"),
      ]
    ),
    .target(
      name: "ExtensionCore",
      dependencies: ["AppKitExtensions", .product(name: "MarkEditCore", package: "TraceCore"), .product(name: "MarkEditKit", package: "TraceKit")],
      path: "Sources/ExtensionCore",
      swiftSettings: [
        .enableExperimentalFeature("StrictConcurrency")
      ],
      plugins: [
        .plugin(name: "SwiftLint", package: "TraceTools"),
      ]
    ),
    .target(
      name: "FileDrop",
      dependencies: ["AppKitExtensions", .product(name: "MarkEditKit", package: "TraceKit"), "TextBundle"],
      path: "Sources/FileDrop",
      swiftSettings: [
        .enableExperimentalFeature("StrictConcurrency")
      ],
      plugins: [
        .plugin(name: "SwiftLint", package: "TraceTools"),
      ]
    ),
    .target(
      name: "FileVersion",
      dependencies: ["SharedUI", .product(name: "MarkEditKit", package: "TraceKit"), "DiffKit"],
      path: "Sources/FileVersion",
      swiftSettings: [
        .enableExperimentalFeature("StrictConcurrency")
      ],
      plugins: [
        .plugin(name: "SwiftLint", package: "TraceTools"),
      ]
    ),
    .target(
      name: "FontPicker",
      dependencies: ["AppKitExtensions"],
      path: "Sources/FontPicker",
      swiftSettings: [
        .enableExperimentalFeature("StrictConcurrency")
      ],
      plugins: [
        .plugin(name: "SwiftLint", package: "TraceTools"),
      ]
    ),
    .target(
      name: "Previewer",
      dependencies: ["AppKitExtensions", .product(name: "MarkEditCore", package: "TraceCore"), .product(name: "MarkEditKit", package: "TraceKit")],
      path: "Sources/Previewer",
      resources: [
        .process("Resources"),
      ],
      swiftSettings: [
        .enableExperimentalFeature("StrictConcurrency")
      ],
      plugins: [
        .plugin(name: "SwiftLint", package: "TraceTools"),
      ]
    ),
    .target(
      name: "SettingsUI",
      dependencies: ["AppKitExtensions"],
      path: "Sources/SettingsUI",
      swiftSettings: [
        .enableExperimentalFeature("StrictConcurrency")
      ],
      plugins: [
        .plugin(name: "SwiftLint", package: "TraceTools"),
      ]
    ),
    .target(
      name: "Statistics",
      dependencies: ["AppKitExtensions", .product(name: "MarkEditKit", package: "TraceKit")],
      path: "Sources/Statistics",
      swiftSettings: [
        .enableExperimentalFeature("StrictConcurrency")
      ],
      plugins: [
        .plugin(name: "SwiftLint", package: "TraceTools"),
      ]
    ),
    .target(
      name: "TextBundle",
      path: "Sources/TextBundle",
      swiftSettings: [
        .enableExperimentalFeature("StrictConcurrency")
      ],
      plugins: [
        .plugin(name: "SwiftLint", package: "TraceTools"),
      ]
    ),
    .target(
      name: "TextCompletion",
      path: "Sources/TextCompletion",
      swiftSettings: [
        .enableExperimentalFeature("StrictConcurrency")
      ],
      plugins: [
        .plugin(name: "SwiftLint", package: "TraceTools"),
      ]
    ),

    .testTarget(
      name: "ModulesTests",
      dependencies: [
        "SharedUI",
        "AppKitExtensions",
        "ExtensionCore",
        "FileDrop",
        "Statistics",
        "TextBundle",
        .product(name: "MarkEditKit", package: "TraceKit"),
      ],
      path: "Tests",
      resources: [
        .copy("Files/sample.textbundle"),
      ],
      plugins: [
        .plugin(name: "SwiftLint", package: "TraceTools"),
      ]
    ),
  ]
)
