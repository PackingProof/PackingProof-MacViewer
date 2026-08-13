// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 PackingProof contributors

import XCTest
@testable import PackingProofViewer

final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (status: Int, data: Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let result = handler(request)
        let response = HTTPURLResponse(
            url: url,
            statusCode: result.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: result.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class HostDiscoveryTests: XCTestCase {
    private let hostNodeId = "123e4567-e89b-12d3-a456-426614174000"

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        configuration.timeoutIntervalForRequest = 2
        return URLSession(configuration: configuration)
    }

    private func validNodeJson(nodeId: String) -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "protocol": "packingproof",
            "protocolVersion": 1,
            "nodeId": nodeId,
            "nodeName": "打包主机",
            "preset": "RecordingHost",
            "capabilities": ["host", "web-playback"],
            "httpPort": 5280
        ])
    }

    private func makeDiscovery(
        addresses: [String] = ["192.0.2.10"],
        nodeId: String? = nil
    ) -> HostDiscovery {
        let expectedNodeId = nodeId ?? hostNodeId
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/node-info")
            return (200, self.validNodeJson(nodeId: expectedNodeId))
        }
        return HostDiscovery(
            session: makeSession(),
            ports: [5280],
            addressProvider: {
                addresses.compactMap(IPv4Address.init(string:))
            }
        )
    }

    func testProbeReturnsValidHost() async {
        let discovery = makeDiscovery()
        let host = await discovery.probe("192.0.2.10:5280")
        XCTAssertNotNil(host)
        XCTAssertEqual(host?.nodeId, hostNodeId)
        XCTAssertEqual(host?.address, "http://192.0.2.10:5280")
        XCTAssertEqual(host?.webURL?.absoluteString, "http://192.0.2.10:5280")
    }

    func testProbeRejectsWrongProtocol() async {
        StubURLProtocol.handler = { _ in
            let data = try! JSONSerialization.data(withJSONObject: [
                "protocol": "other",
                "protocolVersion": 1,
                "nodeId": self.hostNodeId,
                "nodeName": "打包主机",
                "preset": "RecordingHost",
                "capabilities": ["host"],
                "httpPort": 5280
            ])
            return (200, data)
        }
        let discovery = HostDiscovery(
            session: makeSession(),
            ports: [5280],
            addressProvider: { [] }
        )
        let host = await discovery.probe("192.0.2.10:5280")
        XCTAssertNil(host)
    }

    func testProbeRejectsMissingHostCapability() async {
        StubURLProtocol.handler = { _ in
            let data = try! JSONSerialization.data(withJSONObject: [
                "protocol": "packingproof",
                "protocolVersion": 1,
                "nodeId": self.hostNodeId,
                "nodeName": "打包主机",
                "preset": "RecordingHost",
                "capabilities": ["web-playback"],
                "httpPort": 5280
            ])
            return (200, data)
        }
        let discovery = HostDiscovery(
            session: makeSession(),
            ports: [5280],
            addressProvider: { [] }
        )
        let host = await discovery.probe("192.0.2.10:5280")
        XCTAssertNil(host)
    }

    func testProbeRejectsNonHttp200() async {
        StubURLProtocol.handler = { _ in (404, Data()) }
        let discovery = HostDiscovery(
            session: makeSession(),
            ports: [5280],
            addressProvider: { [] }
        )
        let host = await discovery.probe("192.0.2.10:5280")
        XCTAssertNil(host)
    }

    func testDiscoverDeduplicatesByNodeId() async {
        let discovery = makeDiscovery(addresses: ["192.0.2.10", "192.0.2.11"])
        let hosts = await discovery.discover(lastKnownAddress: nil)
        XCTAssertEqual(hosts.count, 1)
        XCTAssertTrue(
            ["http://192.0.2.10:5280", "http://192.0.2.11:5280"].contains(hosts.first?.address ?? "")
        )
    }

    func testDiscoverDoesNotDuplicateLastKnownAddress() async {
        let discovery = makeDiscovery(addresses: ["192.0.2.10", "192.0.2.11"])
        let hosts = await discovery.discover(lastKnownAddress: "192.0.2.10:5280")
        XCTAssertEqual(hosts.count, 1)
    }
}
