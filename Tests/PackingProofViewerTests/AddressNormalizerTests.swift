// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 PackingProof contributors

import XCTest
@testable import PackingProofViewer

final class AddressNormalizerTests: XCTestCase {
    func testBareIpGetsDefaultPort() {
        XCTAssertEqual(AddressNormalizer.normalize("192.168.1.5"), "192.168.1.5:5280")
    }

    func testAddressWithPortIsKept() {
        XCTAssertEqual(AddressNormalizer.normalize("192.168.1.5:6000"), "192.168.1.5:6000")
    }

    func testFullUrlWithPathIsReducedToHostAndPort() {
        XCTAssertEqual(
            AddressNormalizer.normalize("http://192.168.1.5:5280/page?x=1#top"),
            "192.168.1.5:5280"
        )
    }

    func testUrlWithoutPortGetsDefaultPort() {
        XCTAssertEqual(AddressNormalizer.normalize("http://host/path"), "host:5280")
    }

    func testWhitespaceAndTrailingSlashAreIgnored() {
        XCTAssertEqual(AddressNormalizer.normalize(" 192.168.1.5/ "), "192.168.1.5:5280")
    }

    func testEmptyInputStaysEmpty() {
        XCTAssertEqual(AddressNormalizer.normalize(""), "")
        XCTAssertEqual(AddressNormalizer.normalize("   "), "")
    }

    func testConnectionInputParsesAccessKey() {
        let parsed = AddressNormalizer.parseConnection("http://192.168.1.5:5280?key=abc")
        XCTAssertEqual(parsed.address, "192.168.1.5:5280")
        XCTAssertEqual(parsed.accessKey, "abc")
    }

    func testConnectionInputWithoutKey() {
        let parsed = AddressNormalizer.parseConnection("192.168.1.5:5280")
        XCTAssertEqual(parsed.address, "192.168.1.5:5280")
        XCTAssertEqual(parsed.accessKey, "")
    }
}
