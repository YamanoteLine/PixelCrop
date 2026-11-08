// swift-tools-version: 6.1
//
//  PixelCrop — Apple Silicon 专属 macOS 图像剪裁 + 对比工具
//  目标：macOS 26 Tahoe，仅 Apple Silicon
//

import PackageDescription

let package = Package(
    name: "PixelCrop",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "PixelCrop", targets: ["PixelCrop"])
    ],
    targets: [
        .executableTarget(
            name: "PixelCrop",
            path: "Sources/PixelCrop",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreImage"),
                .linkedFramework("ImageIO"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedFramework("SwiftUI")
            ]
        )
    ]
)
