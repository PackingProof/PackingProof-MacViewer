// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 PackingProof contributors

import XCTest
@testable import PackingProofViewer

final class FileWebAccessKeyStoreTests: XCTestCase {
    func testPersistsAndDeletesKeysWithRestrictedPermissions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pp-store-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("keys.json")

        let store = FileWebAccessKeyStore(fileURL: fileURL)
        store.save("key-abc", for: "http://192.0.2.10:5280")

        let reloaded = FileWebAccessKeyStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.key(for: "http://192.0.2.10:5280"), "key-abc")

        reloaded.deleteKey(for: "http://192.0.2.10:5280")
        let afterDelete = FileWebAccessKeyStore(fileURL: fileURL)
        XCTAssertNil(afterDelete.key(for: "http://192.0.2.10:5280"))

        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        XCTAssertEqual(permissions, 0o600)
    }
}
