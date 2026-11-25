// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MateViewGT",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MateViewGT", targets: ["MateViewGTApp"])
    ],
    targets: [
        .target(
            name: "CBridge",
            dependencies: [],
            path: "Sources/CBridge",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedFramework("IOKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("ColorSync"),
                .unsafeFlags([
                    "-F/System/Library/PrivateFrameworks",
                    "-framework", "IOMobileFramebuffer",
                    "-framework", "DisplayServices"
                ])
            ]
        ),
        .executableTarget(
            name: "MateViewGTApp",
            dependencies: ["CBridge"],
            path: "Sources/MateViewGTApp",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ColorSync"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)
