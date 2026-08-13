// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 PackingProof contributors

import Foundation

enum WebAccessProbeResult: Equatable {
    case authorized
    case unauthorized
    case failed
}

/// 网页访问预检：自动跟随重定向。只有最终 200 且最终 URL 严格为主机根路径
/// 才算主机明确接受；401 视为 key 无效，其余情况一律失败。
final class WebAccessProbe {
    private let session: URLSession?

    init(session: URLSession? = nil) {
        self.session = session
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 8
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.connectionProxyDictionary = [:]
        return URLSession(configuration: configuration)
    }

    static func buildWebAccessURL(address: String, key: String?) -> String {
        let normalized = AddressNormalizer.normalize(address)
        let base = "http://\(normalized)/"
        guard let key, !key.isEmpty, var components = URLComponents(string: base) else {
            return base
        }
        components.queryItems = [URLQueryItem(name: "key", value: key)]
        return components.url?.absoluteString ?? base
    }

    static func isStrictRoot(final: URL, expected: URL) -> Bool {
        guard let finalScheme = final.scheme,
              let finalHost = final.host,
              let expectedScheme = expected.scheme,
              let expectedHost = expected.host else {
            return false
        }
        func defaultPort(for scheme: String) -> Int {
            scheme.caseInsensitiveCompare("https") == .orderedSame ? 443 : 80
        }
        let finalPort = final.port ?? defaultPort(for: finalScheme)
        let expectedPort = expected.port ?? defaultPort(for: expectedScheme)
        return finalScheme.caseInsensitiveCompare(expectedScheme) == .orderedSame
            && finalHost.caseInsensitiveCompare(expectedHost) == .orderedSame
            && finalPort == expectedPort
            && final.path == "/"
            && final.query == nil
            && final.fragment == nil
    }

    func probe(address: String, key: String?) async -> WebAccessProbeResult {
        let normalized = AddressNormalizer.normalize(address)
        guard !normalized.isEmpty,
              let url = URL(string: Self.buildWebAccessURL(address: normalized, key: key)) else {
            return .failed
        }

        // 每次预检使用独立会话，避免上一次带 key 请求种下的 cookie 串扰后续探测。
        let activeSession = session ?? Self.makeSession()
        defer {
            if session == nil {
                activeSession.finishTasksAndInvalidate()
            }
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        do {
            let (_, response) = try await activeSession.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .failed }
            if http.statusCode == 401 { return .unauthorized }
            guard http.statusCode == 200,
                  let finalURL = http.url,
                  let expected = URL(string: Self.buildWebAccessURL(address: normalized, key: key)),
                  Self.isStrictRoot(final: finalURL, expected: expected) else {
                return .failed
            }
            return .authorized
        } catch {
            return .failed
        }
    }
}
