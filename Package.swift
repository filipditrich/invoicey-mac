// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "invoicey-mac",
  platforms: [
    .macOS(.v14),
  ],
  products: [
    .library(name: "InvoiceyDriveCore", targets: ["InvoiceyDriveCore"]),
    .library(name: "InvoiceyDriveFileProvider", targets: ["InvoiceyDriveFileProvider"]),
    .executable(name: "InvoiceyDrive", targets: ["InvoiceyDrive"]),
    .executable(name: "invoicey-drive", targets: ["InvoiceyDriveCLI"]),
  ],
  targets: [
    .target(
      name: "InvoiceyDriveCore",
      dependencies: [],
      path: "Sources/InvoiceyDriveCore",
      swiftSettings: [
        .swiftLanguageMode(.v6),
      ]
    ),
    .target(
      name: "InvoiceyDriveFileProvider",
      dependencies: ["InvoiceyDriveCore"],
      path: "Sources/FileProvider",
      exclude: [
        "README.md",
        "InvoiceyDrive.entitlements",
        "InvoiceyDriveFileProvider.entitlements",
      ],
      swiftSettings: [
        .swiftLanguageMode(.v6),
      ],
      linkerSettings: [
        .linkedFramework("FileProvider"),
        .linkedFramework("UniformTypeIdentifiers"),
      ]
    ),
    .executableTarget(
      name: "InvoiceyDrive",
      dependencies: ["InvoiceyDriveCore"],
      path: "Sources/InvoiceyDrive",
      exclude: ["Info.plist"],
      resources: [
        .process("Resources"),
      ],
      swiftSettings: [
        .swiftLanguageMode(.v6),
      ],
      linkerSettings: [
        .linkedFramework("AppKit"),
        .linkedFramework("ServiceManagement"),
      ]
    ),
    .executableTarget(
      name: "InvoiceyDriveCLI",
      dependencies: ["InvoiceyDriveCore"],
      path: "Sources/InvoiceyDriveCLI",
      swiftSettings: [
        .swiftLanguageMode(.v6),
      ]
    ),
    .testTarget(
      name: "InvoiceyDriveCoreTests",
      dependencies: ["InvoiceyDriveCore"],
      path: "Tests/InvoiceyDriveCoreTests",
      swiftSettings: [
        .swiftLanguageMode(.v6),
      ]
    ),
  ]
)
