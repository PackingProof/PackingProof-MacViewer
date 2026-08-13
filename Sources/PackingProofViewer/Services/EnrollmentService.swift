// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 PackingProof contributors

import Foundation

enum EnrollmentError: Error, Equatable {
    case denied(String)
    case upgradeRequired(String)
    case approvalUnavailable(String)
    case notBackupHost(String)
    case requestFailed(String)
    case missingWebAccessUrl
    case network(String)

    var message: String {
        switch self {
        case .denied(let message), .upgradeRequired(let message),
             .approvalUnavailable(let message), .notBackupHost(let message),
             .requestFailed(let message), .network(let message):
            return message
        case .missingWebAccessUrl:
            return "保存主机未返回网页访问链接，请更新保存主机后重试"
        }
    }
}

/// 复用主机的通用设备注册接口 `/api/mobile-backup/enroll`（历史命名，
/// 实际语义是“设备注册 + 主机批准”）：kind=viewer 注册并返回 webAccessUrl。
final class EnrollmentService {
    struct Configuration {
        var timeout: TimeInterval = 90
        var maxBusyRetries = 24
        var retryDelay: @Sendable (TimeInterval) async throws -> Void = {
            try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000))
        }
    }

    private let session: URLSession
    private let configuration: Configuration
    private let deviceId: String
    private let deviceName: String
    private let clientVersion: String

    init(
        deviceId: String = EnrollmentService.persistentDeviceId(),
        deviceName: String = Host.current().localizedName ?? "Mac 查看端",
        clientVersion: String = "0.1.0",
        session: URLSession? = nil,
        configuration: Configuration = Configuration()
    ) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.clientVersion = clientVersion
        self.configuration = configuration
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = configuration.timeout
            config.timeoutIntervalForResource = configuration.timeout
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.connectionProxyDictionary = [:]
            self.session = URLSession(configuration: config)
        }
    }

    /// 成功返回 webAccessUrl；429 按 Retry-After 重试（最多 24 次），
    /// 403/409/426/503 映射为对应错误。
    func enroll(address: String) async throws -> String {
        let normalized = AddressNormalizer.normalize(address)
        guard !normalized.isEmpty,
              let url = URL(string: "http://\(normalized)/api/mobile-backup/enroll") else {
            throw EnrollmentError.network("保存主机地址无效")
        }

        let body: [String: Any] = [
            "deviceId": deviceId,
            "deviceName": deviceName,
            "deviceKind": "viewer",
            "platform": "macos",
            "clientVersion": clientVersion,
            "clientBuildNumber": 0,
            "backupProtocol": "mobile-backup-v2",
            "enrollmentVersion": 2,
            "authVersion": 3
        ]

        for attempt in 0...configuration.maxBusyRetries {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = configuration.timeout
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let data: Data
            let status: Int
            do {
                let (responseData, response) = try await session.data(for: request)
                data = responseData
                status = (response as? HTTPURLResponse)?.statusCode ?? 0
            } catch {
                throw EnrollmentError.network("无法连接保存主机，请检查网络后重试")
            }

            let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            let serverMessage = json["error"] as? String
            switch status {
            case 200...299:
                guard let webAccessUrl = json["webAccessUrl"] as? String,
                      !webAccessUrl.isEmpty else {
                    throw EnrollmentError.missingWebAccessUrl
                }
                return webAccessUrl
            case 429:
                guard attempt < configuration.maxBusyRetries else {
                    throw EnrollmentError.requestFailed("连接请求过于频繁，请稍后重试")
                }
                let delay = (json["retryAfterSeconds"] as? Int).map { TimeInterval($0) } ?? 3
                try await configuration.retryDelay(delay)
            case 403:
                throw EnrollmentError.denied(serverMessage ?? "保存主机已拒绝本次连接")
            case 409:
                throw EnrollmentError.notBackupHost(serverMessage ?? "这台电脑当前不是录像文件备份主机")
            case 426:
                throw EnrollmentError.upgradeRequired(serverMessage ?? "查看端版本过低，请更新后重新连接")
            case 503:
                throw EnrollmentError.approvalUnavailable(
                    serverMessage ?? "电脑端暂时无法显示连接确认窗口，请打开保存主机界面后重试"
                )
            default:
                throw EnrollmentError.requestFailed(
                    serverMessage ?? "保存主机暂时无法处理连接申请，请稍后重试"
                )
            }
        }
        throw EnrollmentError.requestFailed("连接请求过于频繁，请稍后重试")
    }

    private static func persistentDeviceId() -> String {
        let key = "ViewerDeviceId"
        if let saved = UserDefaults.standard.string(forKey: key), saved.count >= 8 {
            return saved
        }
        let generated = UUID().uuidString.lowercased()
        UserDefaults.standard.set(generated, forKey: key)
        return generated
    }
}
