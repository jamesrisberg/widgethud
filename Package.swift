// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "widgetHUD",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "widgetHUDKit", targets: ["widgetHUDKit"]),
        .executable(name: "widgetHUD", targets: ["widgetHUD"]),
        // Installed as Contents/Helpers/widgethud: a distinct product name because widgetHUD and
        // widgethud would collide on a case-insensitive volume.
        .executable(name: "widgetHUDCLI", targets: ["widgetHUDCLI"]),
    ],
    dependencies: [
        // Sibling checkout: ~/dev/hudkit next to ~/dev/widgethud.
        .package(path: "../hudkit"),
    ],
    targets: [
        // Pure core: models, parsing, persistence. No AppKit UI; everything here is unit-tested.
        .target(
            name: "widgetHUDKit",
            path: "Sources/widgetHUDKit"
        ),
        .executableTarget(
            name: "widgetHUD",
            dependencies: ["widgetHUDKit", .product(name: "HUDKit", package: "hudkit")],
            path: "Sources/widgetHUD",
            // Bundle files, assembled into the .app by hudkit/scripts/hud-build.sh.
            exclude: ["Resources"]
        ),
        // `widgethud <command> [key=value ...]`: a thin client for the MacHUD control socket.
        .executableTarget(
            name: "widgetHUDCLI",
            dependencies: [.product(name: "HUDKit", package: "hudkit")],
            path: "Sources/widgetHUDCLI"
        ),
        .testTarget(
            name: "widgetHUDKitTests",
            dependencies: ["widgetHUDKit"],
            path: "Tests/widgetHUDKitTests"
        ),
        // Host logic in the app target and the shipped manifest/settings schema.
        .testTarget(
            name: "widgetHUDTests",
            dependencies: ["widgetHUD", "widgetHUDKit", .product(name: "HUDKit", package: "hudkit")],
            path: "Tests/widgetHUDTests"
        ),
    ]
)
