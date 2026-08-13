// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 PackingProof contributors

import XCTest
@testable import PackingProofViewer

final class RedirectableStubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (status: Int, headers: [String: String], data: Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let result = handler(request)
        if (300...399).contains(result.status), let location = result.headers["Location"] {
            let redirectURL = URL(string: location, relativeTo: url) ?? url
            var redirectedRequest = URLRequest(url: redirectURL)
            redirectedRequest.httpMethod = request.httpMethod
            let redirectResponse = HTTPURLResponse(
                url: url,
                statusCode: result.status,
                httpVersion: "HTTP/1.1",
                headerFields: result.headers
            )!
            client?.urlProtocol(self, wasRedirectedTo: redirectedRequest, redirectResponse: redirectResponse)
            return
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: result.status,
            httpVersion: "HTTP/1.1",
            headerFields: result.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: result.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class WebAccessProbeTests: XCTestCase {
    override func tearDown() {
        RedirectableStubURLProtocol.handler = nil
        super.tearDown()
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RedirectableStubURLProtocol.self]
        configuration.timeoutIntervalForRequest = 2
        return URLSession(configuration: configuration)
    }

    func testBuildWebAccessUrl() {
        XCTAssertEqual(
            WebAccessProbe.buildWebAccessURL(address: "192.168.1.5:5280", key: nil),
            "http://192.168.1.5:5280/"
        )
        XCTAssertEqual(
            WebAccessProbe.buildWebAccessURL(address: "http://192.168.1.5:5280/", key: "abc 123"),
            "http://192.168.1.5:5280/?key=abc%20123"
        )
    }

    func testStrictRootComponentComparison() {
        let expected = URL(string: "http://192.168.1.5:5280/")!
        XCTAssertTrue(WebAccessProbe.isStrictRoot(
            final: URL(string: "http://192.168.1.5:5280/")!,
            expected: expected
        ))
        XCTAssertFalse(WebAccessProbe.isStrictRoot(
            final: URL(string: "http://192.168.1.5:5280")!,
            expected: expected
        ))
        XCTAssertFalse(WebAccessProbe.isStrictRoot(
            final: URL(string: "http://192.168.1.5:5280/index.html")!,
            expected: expected
        ))
        XCTAssertFalse(WebAccessProbe.isStrictRoot(
            final: URL(string: "http://192.168.1.5:5280/web/")!,
            expected: expected
        ))
        XCTAssertFalse(WebAccessProbe.isStrictRoot(
            final: URL(string: "http://192.168.1.5:5280/?key=abc")!,
            expected: expected
        ))
        XCTAssertFalse(WebAccessProbe.isStrictRoot(
            final: URL(string: "http://192.168.1.5:5280/#frag")!,
            expected: expected
        ))
        XCTAssertFalse(WebAccessProbe.isStrictRoot(
            final: URL(string: "http://192.168.1.5:5281/")!,
            expected: expected
        ))
    }

    func testProbeAcceptsRoot200() async {
        RedirectableStubURLProtocol.handler = { _ in (200, [:], Data()) }
        let probe = WebAccessProbe(session: makeSession())
        let result = await probe.probe(address: "192.0.2.10:5280", key: nil)
        XCTAssertEqual(result, .authorized)
    }

    func testProbeFollowsRedirectToRootAndAccepts() async {
        var calls = 0
        RedirectableStubURLProtocol.handler = { request in
            calls += 1
            if request.url?.path == "/" && calls == 1 {
                return (302, ["Location": "/"], Data())
            }
            return (200, [:], Data())
        }
        let probe = WebAccessProbe(session: makeSession())
        let result = await probe.probe(address: "192.0.2.10:5280", key: "k")
        XCTAssertEqual(result, .authorized)
    }

    func testProbeRejectsRedirectToNonRoot() async {
        var calls = 0
        RedirectableStubURLProtocol.handler = { request in
            calls += 1
            if request.url?.path == "/" && calls == 1 {
                return (302, ["Location": "/index.html"], Data())
            }
            return (200, [:], Data())
        }
        let probe = WebAccessProbe(session: makeSession())
        let result = await probe.probe(address: "192.0.2.10:5280", key: "k")
        XCTAssertEqual(result, .failed)
    }

    func testProbeReportsUnauthorized() async {
        RedirectableStubURLProtocol.handler = { _ in (401, [:], Data()) }
        let probe = WebAccessProbe(session: makeSession())
        let result = await probe.probe(address: "192.0.2.10:5280", key: "k")
        XCTAssertEqual(result, .unauthorized)
    }
}
