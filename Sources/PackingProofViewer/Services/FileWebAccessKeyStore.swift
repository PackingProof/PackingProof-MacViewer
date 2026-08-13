// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 PackingProof contributors

import Foundation

/// 开发/本地分发阶段的默认 key 存储：写入用户 Application Support 下的 0600 权限文件。
/// 与 Windows 端把网页 key 保存在 config.json 的安全级别一致，避免 ad-hoc 签名
/// 每次重建导致钥匙串 ACL 反复弹窗。正式 Developer ID 签名后可切换回 Keychain。
final class FileWebAccessKeyStore: WebAccessKeyStoring {
    private let fileURL: URL
    private let lock = NSLock()
    private var cache: [String: String] = [:]

    init(fileURL: URL = FileWebAccessKeyStore.defaultFileURL()) {
        self.fileURL = fileURL
        load()
    }

    static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return base
            .appendingPathComponent("PackingProofViewer", isDirectory: true)
            .appendingPathComponent("web-access-keys.json")
    }

    func key(for host: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return cache[host]
    }

    func save(_ key: String, for host: String) {
        lock.lock()
        cache[host] = key
        persist()
        lock.unlock()
    }

    func deleteKey(for host: String) {
        lock.lock()
        cache.removeValue(forKey: host)
        persist()
        lock.unlock()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return
        }
        cache = decoded
    }

    private func persist() {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )
            let data = try JSONEncoder().encode(cache)
            try data.write(to: fileURL, options: [.atomic])
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
        } catch {
            // 写失败不阻塞查看流程；下次打开会重新申请。
        }
    }
}
