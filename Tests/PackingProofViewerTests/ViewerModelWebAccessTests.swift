// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 PackingProof contributors

import XCTest
@testable import PackingProofViewer

@MainActor
final class ViewerModelWebAccessTests: XCTestCase {
    private final class MemoryKeyStore: WebAccessKeyStoring {
        private var values: [String: String] = [:]

        func key(for host: String) -> String? { values[host] }
        func save(_ key: String, for host: String) { values[host] = key }
        func deleteKey(for host: String) { values.removeValue(forKey: host) }
    }

    private final class URLRecorder {
        var urls: [String] = []
    }

    private let hostAddress = "http://192.0.2.10:5280"

    override func tearDown() {
        RedirectableStubURLProtocol.handler = nil
        super.tearDown()
    }

    private func makeHost(protected: Bool? = true) -> DiscoveredHost {
        DiscoveredHost(
            nodeId: "095c41f0-a7cb-467a-8926-29ddc2446eb6",
            nodeName: "电脑1",
            address: hostAddress,
            capabilitySummary: "host、web-playback",
            accessProtected: protected
        )
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RedirectableStubURLProtocol.self]
        configuration.timeoutIntervalForRequest = 2
        return URLSession(configuration: configuration)
    }

    private func makeModel(
        keyStore: WebAccessKeyStoring,
        session: URLSession,
        recorder: URLRecorder
    ) -> ViewerModel {
        ViewerModel(
            enrollment: EnrollmentService(
                deviceId: "viewer-test-0001",
                deviceName: "Mac 查看端",
                session: session
            ),
            probe: WebAccessProbe(session: session),
            keyStore: keyStore,
            openURL: { url in
                recorder.urls.append(url.absoluteString)
                return true
            }
        )
    }

    /// 模拟真实主机契约：带 ?key= 的根请求先 302 到 "/"，随后 200。
    private static func installWebHandler(keyedStatus: @escaping (String) -> Int) {
        RedirectableStubURLProtocol.handler = { request in
            guard let url = request.url else { return (404, [:], Data()) }
            if url.path == "/api/mobile-backup/enroll" {
                let json = try! JSONSerialization.data(withJSONObject: [
                    "webAccessUrl": "http://192.0.2.10:5280/?key=newkey"
                ])
                return (200, [:], json)
            }
            if url.path == "/" {
                let query = url.query ?? ""
                if let keyRange = query.range(of: "key=") {
                    let key = String(query[keyRange.upperBound...])
                    if keyedStatus(key) == 401 {
                        return (401, [:], Data())
                    }
                    return (302, ["Location": "/"], Data())
                }
                return (200, [:], Data())
            }
            return (404, [:], Data())
        }
    }

    func testProtectedHostEnrollsAndOpensAfterPreflight() async {
        let keyStore = MemoryKeyStore()
        let recorder = URLRecorder()
        Self.installWebHandler(keyedStatus: { _ in 200 })
        let model = makeModel(keyStore: keyStore, session: makeSession(), recorder: recorder)
        model.hosts = [makeHost()]
        model.selectedHostId = makeHost().nodeId

        await model.openWebPlayback()

        XCTAssertEqual(recorder.urls.count, 1)
        XCTAssertTrue(recorder.urls[0].contains("key=newkey"))
        XCTAssertEqual(keyStore.key(for: hostAddress), "newkey")
    }

    func testStaleKeyTriggersSingleReenroll() async {
        let keyStore = MemoryKeyStore()
        keyStore.save("oldkey", for: hostAddress)
        let recorder = URLRecorder()
        var enrollCalls = 0
        RedirectableStubURLProtocol.handler = { request in
            guard let url = request.url else { return (404, [:], Data()) }
            if url.path == "/api/mobile-backup/enroll" {
                enrollCalls += 1
                let json = try! JSONSerialization.data(withJSONObject: [
                    "webAccessUrl": "http://192.0.2.10:5280/?key=newkey"
                ])
                return (200, [:], json)
            }
            if url.path == "/" {
                let query = url.query ?? ""
                if query.contains("oldkey") { return (401, [:], Data()) }
                if query.contains("newkey") { return (302, ["Location": "/"], Data()) }
                return (200, [:], Data())
            }
            return (404, [:], Data())
        }
        let model = makeModel(keyStore: keyStore, session: makeSession(), recorder: recorder)
        model.hosts = [makeHost()]
        model.selectedHostId = makeHost().nodeId

        await model.openWebPlayback()

        XCTAssertEqual(enrollCalls, 1)
        XCTAssertEqual(recorder.urls.count, 1)
        XCTAssertTrue(recorder.urls[0].contains("key=newkey"))
        XCTAssertEqual(keyStore.key(for: hostAddress), "newkey")
    }

    func testProtectedHostNeverOpensWhenPreflightFails() async {
        let keyStore = MemoryKeyStore()
        let recorder = URLRecorder()
        RedirectableStubURLProtocol.handler = { request in
            guard let url = request.url else { return (404, [:], Data()) }
            if url.path == "/api/mobile-backup/enroll" {
                let json = try! JSONSerialization.data(withJSONObject: [
                    "webAccessUrl": "http://192.0.2.10:5280/?key=newkey"
                ])
                return (200, [:], json)
            }
            return (500, [:], Data())
        }
        let model = makeModel(keyStore: keyStore, session: makeSession(), recorder: recorder)
        model.hosts = [makeHost()]
        model.selectedHostId = makeHost().nodeId

        await model.openWebPlayback()

        XCTAssertTrue(recorder.urls.isEmpty)
        XCTAssertNil(keyStore.key(for: hostAddress))
    }

    func testLegacyHostOpensBareOnlyAfterPreflight() async {
        let keyStore = MemoryKeyStore()
        let recorder = URLRecorder()
        RedirectableStubURLProtocol.handler = { request in
            guard let url = request.url else { return (404, [:], Data()) }
            return url.path == "/" ? (200, [:], Data()) : (404, [:], Data())
        }
        let model = makeModel(keyStore: keyStore, session: makeSession(), recorder: recorder)
        model.hosts = [makeHost(protected: nil)]
        model.selectedHostId = makeHost(protected: nil).nodeId

        await model.openWebPlayback()

        XCTAssertEqual(recorder.urls, ["http://192.0.2.10:5280/"])
    }
}
