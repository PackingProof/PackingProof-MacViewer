// swift-tools-version:5.9
// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 PackingProof contributors

import PackageDescription

let package = Package(
    name: "PackingProofViewer",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "PackingProofViewer", targets: ["PackingProofViewer"])
    ],
    targets: [
        .executableTarget(
            name: "PackingProofViewer",
            path: "Sources/PackingProofViewer"
        ),
        .testTarget(
            name: "PackingProofViewerTests",
            dependencies: ["PackingProofViewer"],
            path: "Tests/PackingProofViewerTests"
        )
    ]
)
