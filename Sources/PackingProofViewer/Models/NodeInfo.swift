// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 PackingProof contributors

import Foundation

/// 与 Windows 主机 `GET /api/node-info` 返回结构一一对应的节点信息。
struct NodeInfo: Codable, Sendable {
    let `protocol`: String
    let protocolVersion: Int
    let nodeId: String
    let nodeName: String
    let preset: String
    let capabilities: [String]
    let httpPort: Int

    enum CodingKeys: String, CodingKey {
        case `protocol`
        case protocolVersion
        case nodeId
        case nodeName
        case preset
        case capabilities
        case httpPort
    }

    static let expectedProtocol = "packingproof"
    static let supportedProtocolVersion = 1

    /// 与上游 DeploymentPresets.IsKnown 保持一致。
    static let knownPresets: Set<String> = [
        "RecordingHost",
        "RecordingWorkstation",
        "ViewerClient",
        "MobileBackupHost"
    ]

    /// 与上游 PackingProofNodeInfo.IsValidHost 保持一致的校验。
    var isValidHost: Bool {
        `protocol` == Self.expectedProtocol
            && protocolVersion == Self.supportedProtocolVersion
            && UUID(uuidString: nodeId) != nil
            && Self.knownPresets.contains(preset)
            && capabilities.contains { $0.caseInsensitiveCompare("host") == .orderedSame }
            && (1...65535).contains(httpPort)
    }

    var capabilitySummary: String {
        capabilities.joined(separator: "、")
    }
}

/// 通过校验、可作为“网页回放”入口的主机。
struct DiscoveredHost: Identifiable, Hashable, Sendable {
    let nodeId: String
    let nodeName: String
    let address: String
    let capabilitySummary: String

    var id: String { nodeId }

    var webURL: URL? {
        URL(string: address)
    }
}
