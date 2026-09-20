// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "sleepd",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "sleepd", targets: ["sleepd"])
    ],
    targets: [
        .executableTarget(
            name: "sleepd",
            linkerSettings: [
                .linkedFramework("HealthKit"),
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Resources/Info.plist"
                ])
            ]
        ),
        .testTarget(
            name: "sleepdTests",
            dependencies: ["sleepd"]
        )
    ]
)
