// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 PackingProof contributors

import XCTest
@testable import PackingProofViewer

final class NodeInfoTests: XCTestCase {
    private func makeNode(
        protocolValue: String = "packingproof",
        protocolVersion: Int = 1,
        nodeId: String = "123e4567-e89b-12d3-a456-426614174000",
        nodeName: String = "打包主机",
        preset: String = "RecordingHost",
        capabilities: [String] = ["host", "web-playback"],
        httpPort: Int = 5280,
        accessProtected: Bool? = nil,
        includeAccessProtected: Bool = false
    ) throws -> NodeInfo {
        var object: [String: Any] = [
            "protocol": protocolValue,
            "protocolVersion": protocolVersion,
            "nodeId": nodeId,
            "nodeName": nodeName,
            "preset": preset,
            "capabilities": capabilities,
            "httpPort": httpPort
        ]
        if includeAccessProtected {
            object["accessProtected"] = accessProtected as Any
        }
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(NodeInfo.self, from: data)
    }

    func testValidHostPassesValidation() throws {
        let node = try makeNode()
        XCTAssertTrue(node.isValidHost)
        XCTAssertEqual(node.capabilitySummary, "host、web-playback")
    }

    func testWrongProtocolIsRejected() throws {
        let node = try makeNode(protocolValue: "other")
        XCTAssertFalse(node.isValidHost)
    }

    func testUnsupportedProtocolVersionIsRejected() throws {
        let node = try makeNode(protocolVersion: 2)
        XCTAssertFalse(node.isValidHost)
    }

    func testInvalidNodeIdIsRejected() throws {
        XCTAssertFalse(try makeNode(nodeId: "not-a-guid").isValidHost)
        XCTAssertFalse(try makeNode(nodeId: "").isValidHost)
    }

    func testUnknownPresetIsRejected() throws {
        let node = try makeNode(preset: "SomethingElse")
        XCTAssertFalse(node.isValidHost)
    }

    func testMissingHostCapabilityIsRejected() throws {
        let node = try makeNode(capabilities: ["web-playback"])
        XCTAssertFalse(node.isValidHost)
    }

    func testInvalidHttpPortIsRejected() throws {
        XCTAssertFalse(try makeNode(httpPort: 0).isValidHost)
        XCTAssertFalse(try makeNode(httpPort: 70000).isValidHost)
    }

    func testAccessProtectedIsDecoded() throws {
        XCTAssertNil(try makeNode().accessProtected)
        XCTAssertEqual(
            try makeNode(accessProtected: true, includeAccessProtected: true).accessProtected,
            true
        )
        XCTAssertEqual(
            try makeNode(accessProtected: false, includeAccessProtected: true).accessProtected,
            false
        )
    }
}
