// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 PackingProof contributors

import XCTest
@testable import PackingProofViewer

final class UdpDiscoveryTests: XCTestCase {
    private let nodeId = "123e4567-e89b-12d3-a456-426614174000"

    func testDiscoverRoundTrip() {
        let request = UdpDiscoveryProtocol.encodeDiscover()
        XCTAssertLessThanOrEqual(request.count, UdpDiscoveryProtocol.maxPacketBytes)
        XCTAssertTrue(UdpDiscoveryProtocol.isDiscover(request))
    }

    func testParseAnnounceAcceptsValid() {
        let payload = try! JSONSerialization.data(withJSONObject: [
            "protocol": "packingproof",
            "protocolVersion": 1,
            "action": "announce",
            "nodeId": nodeId,
            "httpPort": 5381
        ])
        let announce = UdpDiscoveryProtocol.parseAnnounce(payload, sourceIp: "192.0.2.10")
        XCTAssertEqual(announce?.nodeId, nodeId)
        XCTAssertEqual(announce?.httpPort, 5381)
        XCTAssertEqual(announce?.sourceIp, "192.0.2.10")
    }

    func testParseAnnounceRejectsInvalid() {
        let cases: [[String: Any]] = [
            ["protocol": "other", "protocolVersion": 1, "action": "announce", "nodeId": nodeId, "httpPort": 5381],
            ["protocol": "packingproof", "protocolVersion": 2, "action": "announce", "nodeId": nodeId, "httpPort": 5381],
            ["protocol": "packingproof", "protocolVersion": 1, "action": "discover", "nodeId": nodeId, "httpPort": 5381],
            ["protocol": "packingproof", "protocolVersion": 1, "action": "announce", "nodeId": "not-a-uuid", "httpPort": 5381],
            ["protocol": "packingproof", "protocolVersion": 1, "action": "announce", "nodeId": nodeId, "httpPort": 0],
            ["protocol": "packingproof", "protocolVersion": 1, "action": "announce", "nodeId": nodeId, "httpPort": 65536],
        ]
        for object in cases {
            let data = try! JSONSerialization.data(withJSONObject: object)
            XCTAssertNil(UdpDiscoveryProtocol.parseAnnounce(data, sourceIp: "192.0.2.10"))
        }
    }

    func testDiscoverRejectsInvalidAction() {
        let payload = try! JSONSerialization.data(withJSONObject: [
            "protocol": "packingproof",
            "protocolVersion": 1,
            "action": "announce"
        ])
        XCTAssertFalse(UdpDiscoveryProtocol.isDiscover(payload))
    }
}
