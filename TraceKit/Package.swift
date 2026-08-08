// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "MarkEditKit",
  platforms: [
    .iOS(.v18),
    .macOS(.v15),
  ],
  products: [
    .library(
      name: "MarkEditKit",
      targets: ["MarkEditKit"]
    ),
  ],
  dependencies: [
    .package(path: "../TraceCore"),
    .package(path: "../TraceTools"),
  ],
  targets: [
    .target(
      name: "MarkEditKit",
      dependencies: [.product(name: "MarkEditCore", package: "TraceCore")],
      path: "Sources",
      swiftSettings: [
        .enableExperimentalFeature("StrictConcurrency")
      ],
      plugins: [
        .plugin(name: "SwiftLint", package: "TraceTools"),
      ]
    ),
  ]
)
