// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CPAUsageMenuBar",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "CPAUsageMenuBar", targets: ["CPAUsageMenuBar"])
    ],
    targets: [
        .executableTarget(
            name: "CPAUsageMenuBar",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Security"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .testTarget(
            name: "CPAUsageMenuBarTests",
            dependencies: ["CPAUsageMenuBar"],
            swiftSettings: [
                .unsafeFlags(["-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"
                ]),
                .linkedFramework("Testing")
            ]
        )
    ]
)
