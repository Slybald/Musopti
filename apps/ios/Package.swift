// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Musopti",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "MusoptiCore",
            targets: ["MusoptiCore"]
        ),
    ],
    targets: [
        /*
         * This SwiftPM package is used for unit-testing the non-UI logic on macOS.
         * The actual iOS app is built via Xcode.
         */
        .target(
            name: "MusoptiCore",
            path: "Musopti",
            exclude: [
                "App",
                "Views",
                "Models",
                "Services",
                "Resources",
                "BLE/BLEManager.swift",
                "BLE/DeviceStatus.swift",
                "Utilities/Extensions.swift",
                "Utilities/WorkoutMetrics.swift",
                "Musopti.entitlements",
            ]
            ,
            sources: [
                "BLE/BLEConstants.swift",
                "BLE/MusoptiEvent.swift",
                "BLE/MusoptiConfig.swift",
                "BLE/MusoptiStatus.swift",
                "BLE/BLESyncEvaluator.swift",
                "BLE/RawDataParser.swift",
                "Utilities/DataParsing.swift",
                "Utilities/MotionPhase.swift",
            ]
        ),
        .testTarget(
            name: "MusoptiCoreTests",
            dependencies: ["MusoptiCore"],
            path: "MusoptiTests"
        ),
    ]
)
