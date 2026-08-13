// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 PackingProof contributors

import XCTest
@testable import PackingProofViewer

final class EnrollmentServiceTests: XCTestCase {
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

    private func makeService(
        session: URLSession,
        retryDelay: @escaping @Sendable (TimeInterval) async throws -> Void = { _ in }
    ) -> EnrollmentService {
        var configuration = EnrollmentService.Configuration()
        configuration.maxBusyRetries = 2
        configuration.retryDelay = retryDelay
        return EnrollmentService(
            deviceId: "viewer-test-0001",
            deviceName: "Mac 查看端",
            session: session,
            configuration: configuration
        )
    }

    func testEnrollReturnsWebAccessUrl() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/mobile-backup/enroll")
            XCTAssertEqual(request.httpMethod, "POST")
            let json = try! JSONSerialization.data(withJSONObject: [
                "webAccessUrl": "http://192.0.2.10:5280/?key=abc"
            ])
            return (200, json)
        }
        let url = try await makeService(session: makeSession()).enroll(address: "192.0.2.10:5280")
        XCTAssertEqual(url, "http://192.0.2.10:5280/?key=abc")
    }

    func testEnrollThrowsWhenWebAccessUrlMissing() async {
        StubURLProtocol.handler = { _ in (200, Data("{}".utf8)) }
        do {
            _ = try await makeService(session: makeSession()).enroll(address: "192.0.2.10:5280")
            XCTFail("应当抛出 missingWebAccessUrl")
        } catch {
            XCTAssertEqual(error as? EnrollmentError, .missingWebAccessUrl)
        }
    }

    func testEnrollRetriesOnBusy() async throws {
        var calls = 0
        StubURLProtocol.handler = { _ in
            calls += 1
            if calls == 1 {
                let json = try! JSONSerialization.data(withJSONObject: [
                    "retryAfterSeconds": 0
                ])
                return (429, json)
            }
            let json = try! JSONSerialization.data(withJSONObject: [
                "webAccessUrl": "http://192.0.2.10:5280/?key=abc"
            ])
            return (200, json)
        }
        let url = try await makeService(session: makeSession()).enroll(address: "192.0.2.10:5280")
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(url, "http://192.0.2.10:5280/?key=abc")
    }

    func testEnrollMapsDenied() async {
        let json = try! JSONSerialization.data(withJSONObject: ["error": "保存主机已拒绝本次连接"])
        StubURLProtocol.handler = { _ in (403, json) }
        do {
            _ = try await makeService(session: makeSession()).enroll(address: "192.0.2.10:5280")
            XCTFail("应当抛出 denied")
        } catch {
            XCTAssertEqual(error as? EnrollmentError, .denied("保存主机已拒绝本次连接"))
        }
    }
}
