// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 PackingProof contributors

import SwiftUI

/// 只保留 PackingProof 品牌色与图标约定，其余颜色走系统语义色以跟随明暗主题。
enum AppTheme {
    static let accentBlue = Color(red: 0x3B / 255.0, green: 0x82 / 255.0, blue: 0xF6 / 255.0)
    static let successGreen = Color(red: 0x10 / 255.0, green: 0xB9 / 255.0, blue: 0x81 / 255.0)
    static let errorRed = Color(red: 0xEF / 255.0, green: 0x44 / 255.0, blue: 0x44 / 255.0)

    enum Symbol {
        static let search = "arrow.clockwise"
        static let manualConnect = "link"
        static let changeHost = "arrow.triangle.2.circlepath"
        static let play = "safari.fill"
        static let noHost = "wifi.slash"
    }
}
