// swift-tools-version:5.9
// IMECore：嘸蝦米 / .cin 輸入引擎。只依賴 Foundation，不 import UIKit，
// 可在 Linux / Windows / macOS 上 `swift test`（NFR-10）。
import PackageDescription

let package = Package(
    name: "IMECore",
    platforms: [
        .iOS(.v17),
        .macOS(.v13),
    ],
    products: [
        .library(name: "IMECore", targets: ["IMECore"]),
    ],
    targets: [
        .target(name: "IMECore"),
        .testTarget(
            name: "IMECoreTests",
            dependencies: ["IMECore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
