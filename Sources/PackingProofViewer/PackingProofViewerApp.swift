// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 PackingProof contributors

import SwiftUI

@main
struct PackingProofViewerApp: App {
    var body: some Scene {
        WindowGroup("PackingProof 查看端") {
            ContentView()
                .frame(width: 520, height: 300)
        }
        .windowResizability(.contentSize)
    }
}
