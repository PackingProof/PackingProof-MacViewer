// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 PackingProof contributors

import XCTest
@testable import PackingProofViewer

final class IPv4SubnetTests: XCTestCase {
    func testIpv4AddressParsingAndDescription() {
        let address = IPv4Address(string: "192.168.1.5")
        XCTAssertEqual(address?.value, 0xc0a80105)
        XCTAssertEqual(address?.description, "192.168.1.5")
        XCTAssertNil(IPv4Address(string: "192.168.1"))
        XCTAssertNil(IPv4Address(string: "192.168.1.999"))
    }

    func testUsableLanAddressFilter() {
        XCTAssertFalse(IPv4Address(string: "0.1.2.3")!.isUsableLanAddress)
        XCTAssertFalse(IPv4Address(string: "169.254.1.1")!.isUsableLanAddress)
        XCTAssertFalse(IPv4Address(string: "224.0.0.1")!.isUsableLanAddress)
        XCTAssertFalse(IPv4Address(string: "255.255.255.255")!.isUsableLanAddress)
        XCTAssertFalse(IPv4Address(string: "198.18.0.1")!.isUsableLanAddress)
        XCTAssertTrue(IPv4Address(string: "192.168.1.1")!.isUsableLanAddress)
    }

    func testPrivateLanAddressFilter() {
        XCTAssertTrue(IPv4Address(string: "10.0.0.1")!.isPrivateLanAddress)
        XCTAssertTrue(IPv4Address(string: "172.16.0.1")!.isPrivateLanAddress)
        XCTAssertTrue(IPv4Address(string: "172.31.255.254")!.isPrivateLanAddress)
        XCTAssertTrue(IPv4Address(string: "192.168.1.1")!.isPrivateLanAddress)
        XCTAssertFalse(IPv4Address(string: "172.32.0.1")!.isPrivateLanAddress)
        XCTAssertFalse(IPv4Address(string: "100.64.0.1")!.isPrivateLanAddress)
    }

    func testContiguousMaskCheck() {
        XCTAssertTrue(SubnetEnumerator.isContiguousMask(0xffffff00))
        XCTAssertTrue(SubnetEnumerator.isContiguousMask(0xffff0000))
        XCTAssertFalse(SubnetEnumerator.isContiguousMask(0xff00ff00))
    }

    func testSlash24Enumerates254HostsWithoutNetworkAndBroadcast() {
        let address = IPv4Address(string: "192.168.1.37")!
        let hosts = SubnetEnumerator.enumerate(address: address, mask: 0xffffff00)
        XCTAssertEqual(hosts.count, 254)
        XCTAssertEqual(hosts.first?.description, "192.168.1.1")
        XCTAssertEqual(hosts.last?.description, "192.168.1.254")
        XCTAssertTrue(hosts.contains(address))
    }

    func testNonContiguousMaskFallsBackToSlash24() {
        let hosts = SubnetEnumerator.enumerate(
            address: IPv4Address(string: "192.168.1.37")!,
            mask: 0xff00ff00
        )
        XCTAssertEqual(hosts.count, 254)
    }

    func testOversizedSubnetIsCappedToSlash24() {
        let hosts = SubnetEnumerator.enumerate(
            address: IPv4Address(string: "10.20.1.37")!,
            mask: 0xffff0000
        )
        XCTAssertEqual(hosts.count, 254)
        XCTAssertEqual(hosts.first?.description, "10.20.1.1")
        XCTAssertEqual(hosts.last?.description, "10.20.1.254")
    }
}
